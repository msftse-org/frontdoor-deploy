mock_provider "azurerm" {}
variables {
  resource_group_name = "rg-test"
  policy              = { name = "wafTest", security_policy_name = "security-default" }
}
run "detection_baseline" {
  command = plan
  module { source = "./modules/waf-policy" }
  assert {
    condition     = azurerm_cdn_frontdoor_firewall_policy.this.enabled && azurerm_cdn_frontdoor_firewall_policy.this.mode == "Detection" && azurerm_cdn_frontdoor_firewall_policy.this.request_body_check_enabled
    error_message = "WAF must start enabled in Detection with body inspection."
  }
  assert {
    condition     = length(azurerm_cdn_frontdoor_firewall_policy.this.managed_rule) == 2
    error_message = "DRS and Bot Manager must be enabled by default."
  }
}
run "reject_missing_managed_rules" {
  command = plan
  module { source = "./modules/waf-policy" }
  variables { policy = { name = "wafTest", security_policy_name = "security-default", managed_rules = [] } }
  expect_failures = [var.policy]
}
run "reject_duplicate_priorities" {
  command = plan
  module { source = "./modules/waf-policy" }
  variables {
    policy = { name = "wafTest", security_policy_name = "security-default", custom_rules = {
      one = { name = "One", priority = 10, match_conditions = [{ match_variable = "RequestUri", operator = "Contains", match_values = ["/one"] }] }
      two = { name = "Two", priority = 10, match_conditions = [{ match_variable = "RequestUri", operator = "Contains", match_values = ["/two"] }] }
    } }
  }
  expect_failures = [var.policy]
}

run "explicit_prevention_after_tuning" {
  command = plan
  module { source = "./modules/waf-policy" }
  variables {
    policy = { name = "wafTest", security_policy_name = "security-default", mode = "Prevention" }
  }
  assert {
    condition     = azurerm_cdn_frontdoor_firewall_policy.this.mode == "Prevention"
    error_message = "Customers must be able to explicitly enable Prevention after tuning."
  }
}
