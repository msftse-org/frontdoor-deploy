locals {
  rules = merge({}, [
    for set_key, rule_set in var.config.rule_sets : {
      for rule_key, rule in rule_set.rules : "${set_key}/${rule_key}" => merge(rule, { set_key = set_key })
    }
  ]...)
}

resource "azurerm_cdn_frontdoor_rule_set" "this" {
  for_each = var.config.rule_sets

  name                     = each.value.name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
}

resource "azurerm_cdn_frontdoor_rule" "this" {
  for_each = local.rules

  name                      = each.value.name
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.this[each.value.set_key].id
  order                     = each.value.order
  behaviour_on_match        = each.value.behaviour_on_match

  actions {
    dynamic "modify_response_header" {
      for_each = each.value.response_headers
      content {
        header_name  = modify_response_header.value.name
        operator     = modify_response_header.value.action
        header_value = modify_response_header.value.value
      }
    }
    dynamic "modify_request_header" {
      for_each = each.value.request_headers
      content {
        header_name  = modify_request_header.value.name
        operator     = modify_request_header.value.action
        header_value = modify_request_header.value.value
      }
    }
    dynamic "url_rewrite" {
      for_each = each.value.url_rewrite == null ? [] : [each.value.url_rewrite]
      content {
        source_pattern                  = url_rewrite.value.source_pattern
        destination_path                = url_rewrite.value.destination_path
        preserve_unmatched_path_enabled = url_rewrite.value.preserve_unmatched_path
      }
    }
    dynamic "url_redirect" {
      for_each = each.value.url_redirect == null ? [] : [each.value.url_redirect]
      content {
        redirect_type         = url_redirect.value.redirect_type
        redirect_protocol     = "Https"
        destination_host_name = url_redirect.value.destination_host_name
        destination_path      = url_redirect.value.destination_path
        query_string          = url_redirect.value.query_string
        destination_fragment  = url_redirect.value.destination_fragment
      }
    }
  }

  dynamic "conditions" {
    for_each = each.value.path_condition == null ? [] : [each.value.path_condition]
    content {
      request_path {
        operator   = conditions.value.operator
        values     = conditions.value.values
        transforms = conditions.value.transforms
      }
    }
  }
}
