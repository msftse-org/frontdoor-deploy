resource "azurerm_cdn_frontdoor_secret" "this" {
  for_each = var.config.certificates

  name                     = each.value.name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  secret {
    customer_certificate {
      key_vault_certificate_id = each.value.key_vault_certificate_id
    }
  }

  depends_on = [azurerm_role_assignment.profile]
}

resource "azurerm_cdn_frontdoor_custom_domain" "this" {
  for_each = var.config.custom_domains

  name                     = each.value.name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  host_name                = each.value.host_name
  dns_zone_id              = each.value.dns_zone_id

  tls {
    certificate_type        = each.value.certificate_key == null ? "ManagedCertificate" : "CustomerCertificate"
    cdn_frontdoor_secret_id = each.value.certificate_key == null ? null : azurerm_cdn_frontdoor_secret.this[each.value.certificate_key].id
    minimum_version         = "TLS12"
  }
}
