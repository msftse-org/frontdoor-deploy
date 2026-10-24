mock_provider "azurerm" {}

variables {
  resource_group_name = "rg-test"
  config = {
    "name" = "afd-customer-prod"
    "endpoints" = {
      "public" = {
        "name" = "fde-customer-prod-unique"
      }
    }
    "origin_groups" = {
      "web" = {
        "name" = "og-web"
        "origins" = {
          "primary" = {
            "name"      = "origin-customer-web"
            "host_name" = "customer-web.azurewebsites.net"
            "priority"  = 1
            "private_link" = {
              "target_resource_id" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-existing-app/providers/Microsoft.Web/sites/customer-web"
              "location"           = "westeurope"
              "target_type"        = "sites"
              "request_message"    = "afd-customer-prod: customer-web"
            }
          }
          "backup" = {
            "name"      = "origin-customer-web-backup"
            "host_name" = "customer-web-backup.azurewebsites.net"
            "priority"  = 2
            "private_link" = {
              "target_resource_id" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-existing-app/providers/Microsoft.Web/sites/customer-web-backup"
              "location"           = "westeurope"
              "target_type"        = "sites"
              "request_message"    = "afd-customer-prod: customer-web-backup"
            }
          }
        }
      }
      "api" = {
        "name" = "og-api"
        "health_probe" = {
          "path"         = "/health"
          "request_type" = "GET"
        }
        "origins" = {
          "primary" = {
            "name"      = "origin-customer-api"
            "host_name" = "customer-api.azurewebsites.net"
            "priority"  = 1
            "private_link" = {
              "target_resource_id" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-existing-app/providers/Microsoft.Web/sites/customer-api"
              "location"           = "westeurope"
              "target_type"        = "sites"
              "request_message"    = "afd-customer-prod: customer-api"
            }
          }
        }
      }
    }
    "routes" = {
      "web" = {
        "name"              = "route-web"
        "endpoint_key"      = "public"
        "origin_group_key"  = "web"
        "patterns_to_match" = ["/*"]
        "rule_set_keys"     = ["headers"]
      }
      "api" = {
        "name"              = "route-api"
        "endpoint_key"      = "public"
        "origin_group_key"  = "api"
        "patterns_to_match" = ["/api", "/api/*"]
        "rule_set_keys"     = ["headers"]
      }
      "static" = {
        "name"              = "route-static"
        "endpoint_key"      = "public"
        "origin_group_key"  = "web"
        "patterns_to_match" = ["/assets/*"]
        "cache" = {
          "query_string_caching_behavior" = "UseQueryString"
          "compression_enabled"           = true
          "content_types_to_compress"     = ["text/css", "application/javascript"]
        }
      }
    }
    "rule_sets" = {
      "headers" = {
        "name" = "SecurityHeaders"
        "rules" = {
          "baseline" = {
            "name"  = "Baseline"
            "order" = 0
            "response_headers" = [{
              "name"  = "X-Content-Type-Options"
              "value" = "nosniff"
              }, {
              "name"  = "Strict-Transport-Security"
              "value" = "max-age=31536000"
            }]
          }
        }
      }
    }
  }
  waf_policies = { default = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/frontDoorWebApplicationFirewallPolicies/wafTest", security_policy_name = "security-default" } }
}

run "private_multi_app_baseline" {
  command = plan
  module { source = "./modules/front-door" }
  assert {
    condition     = azurerm_cdn_frontdoor_profile.this.sku_name == "Premium_AzureFrontDoor"
    error_message = "Premium is required for Private Link."
  }
  assert {
    condition     = length(azurerm_cdn_frontdoor_origin.this) == 3 && length(azurerm_cdn_frontdoor_origin_group.this) == 2 && length(azurerm_cdn_frontdoor_route.this) == 3
    error_message = "Multi-app and failover topology must expand from configuration."
  }
  assert {
    condition     = alltrue([for origin in azurerm_cdn_frontdoor_origin.this : origin.certificate_name_check_enabled && length(origin.private_link) == 1])
    error_message = "All origins must use Private Link and certificate name checks."
  }
  assert {
    condition     = alltrue([for route in azurerm_cdn_frontdoor_route.this : route.forwarding_protocol == "HttpsOnly" && route.https_redirect_enabled])
    error_message = "All routes must enforce HTTPS."
  }
  assert {
    condition     = length(azurerm_cdn_frontdoor_route.this["api"].cache) == 0 && length(azurerm_cdn_frontdoor_route.this["static"].cache) == 1
    error_message = "Cache must be opt-in and remain off for the API."
  }
  assert {
    condition     = length(azurerm_cdn_frontdoor_security_policy.this) == 1 && azurerm_cdn_frontdoor_security_policy.this["default"].security_policies[0].firewall[0].association[0].patterns_to_match == tolist(["/*"])
    error_message = "WAF must cover all endpoint paths."
  }
  assert {
    condition     = azurerm_cdn_frontdoor_origin.this["web/backup"].priority == 2
    error_message = "Failover priority must be retained."
  }
}

run "reject_unprotected_endpoint" {
  command = plan
  module { source = "./modules/front-door" }
  variables { waf_policies = {} }
  expect_failures = [var.waf_policies]
}

run "reject_empty_origin_group" {
  command = plan
  module { source = "./modules/front-door" }
  variables {
    config = merge(var.config, { origin_groups = { web = { name = "og-web", origins = {} }, api = var.config.origin_groups.api } })
  }
  expect_failures = [var.config]
}

run "reject_unreachable_route" {
  command = plan
  module { source = "./modules/front-door" }
  variables {
    config = merge(var.config, { routes = { web = { name = "route-web", endpoint_key = "public", origin_group_key = "web", link_to_default_domain = false } } })
  }
  expect_failures = [var.config]
}

run "custom_domain_and_second_policy" {
  command = plan
  module { source = "./modules/front-door" }
  variables {
    config = merge(var.config, {
      custom_domains = { api = { name = "domain-api", host_name = "api.example.com", waf_policy_key = "api" } }
      routes = { api = {
        name               = "route-api", endpoint_key = "public", origin_group_key = "api"
        custom_domain_keys = ["api"], link_to_default_domain = false
      } }
    })
    waf_policies = merge(var.waf_policies, {
      api = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/frontDoorWebApplicationFirewallPolicies/wafApi", security_policy_name = "security-api" }
    })
  }
  assert {
    condition     = length(azurerm_cdn_frontdoor_security_policy.this) == 2 && length(azurerm_cdn_frontdoor_custom_domain.this) == 1
    error_message = "Custom domains and the default endpoint must both have their chosen WAF policies."
  }
  assert {
    condition     = azurerm_cdn_frontdoor_custom_domain.this["api"].tls[0].minimum_version == "TLS12"
    error_message = "Custom domains must require TLS 1.2 or higher."
  }
}

run "rewrite_with_path_condition" {
  command = plan
  module { source = "./modules/front-door" }
  variables {
    config = merge(var.config, {
      rule_sets = { headers = { name = "Rewrite", rules = { path = {
        name           = "RewritePath", order = 1
        path_condition = { operator = "BeginsWith", values = ["rewrite/"] }
        url_rewrite    = { source_pattern = "/rewrite/", destination_path = "/changed/" }
      } } } }
    })
  }
  assert {
    condition     = azurerm_cdn_frontdoor_rule.this["headers/path"].actions[0].url_rewrite[0].preserve_unmatched_path_enabled
    error_message = "Rewrite should preserve the unmatched path suffix."
  }
}

run "reject_conflicting_rule_actions" {
  command = plan
  module { source = "./modules/front-door" }
  variables {
    config = merge(var.config, {
      rule_sets = { headers = { name = "Conflicting", rules = { conflict = {
        name         = "Conflict", order = 0
        url_rewrite  = { source_pattern = "/old/", destination_path = "/new/" }
        url_redirect = { destination_path = "/elsewhere/" }
      } } } }
    })
  }
  expect_failures = [var.config]
}
