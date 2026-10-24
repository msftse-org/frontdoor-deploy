output "endpoint_urls" {
  description = "HTTPS URLs for enabled endpoints with an enabled route linked to the default domain."
  value = {
    for key, endpoint in module.front_door.endpoints : key => "https://${endpoint.host_name}"
    if var.front_door.endpoints[key].enabled && anytrue([
      for route in values(var.front_door.routes) : route.endpoint_key == key && route.enabled && route.link_to_default_domain
    ])
  }
}

output "front_door" {
  description = "Profile, identity, endpoints, routing IDs, DNS validation, and Private Link targets."
  value       = module.front_door
}

output "waf_policy_ids" {
  description = "WAF policy resource IDs keyed by configuration key."
  value       = { for key, policy in module.waf : key => policy.id }
}
