resource "azurerm_cdn_frontdoor_route" "this" {
  for_each = var.config.routes

  name                            = each.value.name
  cdn_frontdoor_endpoint_id       = azurerm_cdn_frontdoor_endpoint.this[each.value.endpoint_key].id
  cdn_frontdoor_origin_group_id   = azurerm_cdn_frontdoor_origin_group.this[each.value.origin_group_key].id
  cdn_frontdoor_origin_ids        = [for key, origin in local.origins : azurerm_cdn_frontdoor_origin.this[key].id if origin.group_key == each.value.origin_group_key]
  cdn_frontdoor_custom_domain_ids = [for key in each.value.custom_domain_keys : azurerm_cdn_frontdoor_custom_domain.this[key].id]
  cdn_frontdoor_rule_set_ids      = [for key in each.value.rule_set_keys : azurerm_cdn_frontdoor_rule_set.this[key].id]
  cdn_frontdoor_origin_path       = each.value.origin_path
  enabled                         = each.value.enabled
  patterns_to_match               = each.value.patterns_to_match
  link_to_default_domain          = each.value.link_to_default_domain
  forwarding_protocol             = "HttpsOnly"
  https_redirect_enabled          = true
  supported_protocols             = ["Http", "Https"]

  dynamic "cache" {
    for_each = each.value.cache == null ? [] : [each.value.cache]
    content {
      query_string_caching_behavior = cache.value.query_string_caching_behavior
      query_strings                 = cache.value.query_strings
      compression_enabled           = cache.value.compression_enabled
      content_types_to_compress     = cache.value.content_types_to_compress
    }
  }

  # Create protection and rules before a route can serve traffic.
  depends_on = [azurerm_cdn_frontdoor_security_policy.this, azurerm_cdn_frontdoor_rule.this]
}
