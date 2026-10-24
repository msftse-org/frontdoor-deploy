resource "azurerm_cdn_frontdoor_profile" "this" {
  name                     = var.config.name
  resource_group_name      = var.resource_group_name
  sku_name                 = "Premium_AzureFrontDoor"
  response_timeout_seconds = var.config.response_timeout_seconds
  tags                     = var.tags

  identity {
    type         = length(var.config.user_assigned_identity_ids) == 0 ? "SystemAssigned" : "SystemAssigned, UserAssigned"
    identity_ids = var.config.user_assigned_identity_ids
  }
}

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  for_each = var.config.endpoints

  name                     = each.value.name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  enabled                  = each.value.enabled
  tags                     = var.tags
}

# These grants are for the profile identity (for example, Key Vault certificate access).
# Private Link origins do not support Front Door managed-identity origin authentication.
resource "azurerm_role_assignment" "profile" {
  for_each = var.config.identity_role_assignments

  scope                            = each.value.scope
  role_definition_name             = each.value.role_definition_name
  principal_id                     = azurerm_cdn_frontdoor_profile.this.identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
