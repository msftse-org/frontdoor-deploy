locals {
  origins = merge({}, [
    for group_key, group in var.config.origin_groups : {
      for origin_key, origin in group.origins : "${group_key}/${origin_key}" => merge(origin, { group_key = group_key })
    }
  ]...)
}

resource "azurerm_cdn_frontdoor_origin_group" "this" {
  for_each = var.config.origin_groups

  name                     = each.value.name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  session_affinity_enabled = each.value.session_affinity_enabled

  health_probe {
    protocol            = "Https"
    path                = each.value.health_probe.path
    request_type        = each.value.health_probe.request_type
    interval_in_seconds = each.value.health_probe.interval_in_seconds
  }

  load_balancing {
    sample_size                        = each.value.load_balancing.sample_size
    successful_samples_required        = each.value.load_balancing.successful_samples_required
    additional_latency_in_milliseconds = each.value.load_balancing.additional_latency_in_milliseconds
  }
}

resource "azurerm_cdn_frontdoor_origin" "this" {
  for_each = local.origins

  name                           = each.value.name
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.this[each.value.group_key].id
  host_name                      = each.value.host_name
  origin_host_header             = coalesce(each.value.origin_host_header, each.value.host_name)
  enabled                        = each.value.enabled
  certificate_name_check_enabled = true
  http_port                      = 80
  https_port                     = each.value.https_port
  priority                       = each.value.priority
  weight                         = each.value.weight

  private_link {
    private_link_target_id = each.value.private_link.target_resource_id
    target_type            = each.value.private_link.target_type
    location               = each.value.private_link.location
    request_message        = each.value.private_link.request_message
  }
}
