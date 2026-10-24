locals {
  policy_domains = {
    for key, policy in var.waf_policies : key => concat(
      [for endpoint_key, endpoint in var.config.endpoints : azurerm_cdn_frontdoor_endpoint.this[endpoint_key].id if endpoint.waf_policy_key == key],
      [for domain_key, domain in var.config.custom_domains : azurerm_cdn_frontdoor_custom_domain.this[domain_key].id if domain.waf_policy_key == key]
    )
  }
}

resource "azurerm_cdn_frontdoor_security_policy" "this" {
  for_each = { for key, policy in var.waf_policies : key => policy if length(local.policy_domains[key]) > 0 }

  name                     = each.value.security_policy_name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = each.value.id
      association {
        patterns_to_match = ["/*"]
        dynamic "domain" {
          for_each = local.policy_domains[each.key]
          content {
            cdn_frontdoor_domain_id = domain.value
          }
        }
      }
    }
  }
}
