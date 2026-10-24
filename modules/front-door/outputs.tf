output "profile_id" {
  description = "Front Door profile resource ID."
  value       = azurerm_cdn_frontdoor_profile.this.id
}

output "profile_resource_guid" {
  description = "Front Door identifier used in X-Azure-FDID."
  value       = azurerm_cdn_frontdoor_profile.this.resource_guid
}

output "identity_principal_id" {
  description = "System-assigned profile identity principal ID."
  value       = azurerm_cdn_frontdoor_profile.this.identity[0].principal_id
}

output "endpoints" {
  description = "Endpoint IDs and generated hostnames; do not construct azurefd.net names yourself."
  value       = { for key, endpoint in azurerm_cdn_frontdoor_endpoint.this : key => { id = endpoint.id, host_name = endpoint.host_name } }
}

output "route_ids" {
  description = "Route IDs keyed by stable configuration key."
  value       = { for key, route in azurerm_cdn_frontdoor_route.this : key => route.id }
}

output "custom_domain_validation" {
  description = "DNS ownership tokens and expiry; create TXT records with your DNS provider."
  value = { for key, domain in azurerm_cdn_frontdoor_custom_domain.this : key => {
    host_name        = domain.host_name
    validation_token = domain.validation_token
    expiration_date  = domain.expiration_date
  } }
}

output "private_link_targets" {
  description = "Targets on which the resource owner must approve the specific Front Door connection."
  value       = { for key, origin in local.origins : key => origin.private_link }
}
