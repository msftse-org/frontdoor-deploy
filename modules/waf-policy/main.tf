resource "azurerm_cdn_frontdoor_firewall_policy" "this" {
  name                              = var.policy.name
  resource_group_name               = var.resource_group_name
  sku_name                          = "Premium_AzureFrontDoor"
  enabled                           = true
  mode                              = var.policy.mode
  request_body_check_enabled        = true
  redirect_url                      = var.policy.redirect_url
  custom_block_response_status_code = var.policy.custom_block_response_status_code
  custom_block_response_body        = var.policy.custom_block_response_body
  tags                              = var.tags

  dynamic "custom_rule" {
    for_each = var.policy.custom_rules
    content {
      name                           = custom_rule.value.name
      priority                       = custom_rule.value.priority
      type                           = custom_rule.value.type
      action                         = custom_rule.value.action
      enabled                        = custom_rule.value.enabled
      rate_limit_duration_in_minutes = custom_rule.value.rate_limit_duration_in_minutes
      rate_limit_threshold           = custom_rule.value.rate_limit_threshold

      dynamic "match_condition" {
        for_each = custom_rule.value.match_conditions
        content {
          match_variable     = match_condition.value.match_variable
          operator           = match_condition.value.operator
          match_values       = match_condition.value.match_values
          selector           = match_condition.value.selector
          negation_condition = match_condition.value.negation_condition
          transforms         = match_condition.value.transforms
        }
      }
    }
  }

  dynamic "managed_rule" {
    for_each = var.policy.managed_rules
    content {
      type    = managed_rule.value.type
      version = managed_rule.value.version
      action  = managed_rule.value.action

      dynamic "exclusion" {
        for_each = managed_rule.value.exclusions
        content {
          match_variable = exclusion.value.match_variable
          operator       = exclusion.value.operator
          selector       = exclusion.value.selector
        }
      }
      dynamic "override" {
        for_each = managed_rule.value.overrides
        content {
          rule_group_name = override.value.rule_group_name
          dynamic "exclusion" {
            for_each = override.value.exclusions
            content {
              match_variable = exclusion.value.match_variable
              operator       = exclusion.value.operator
              selector       = exclusion.value.selector
            }
          }
          dynamic "rule" {
            for_each = override.value.rules
            content {
              rule_id = rule.value.rule_id
              enabled = rule.value.enabled
              action  = rule.value.action
              dynamic "exclusion" {
                for_each = rule.value.exclusions
                content {
                  match_variable = exclusion.value.match_variable
                  operator       = exclusion.value.operator
                  selector       = exclusion.value.selector
                }
              }
            }
          }
        }
      }
    }
  }
}
