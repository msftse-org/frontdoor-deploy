resource "azurerm_resource_group" "this" {
  count = var.resource_group.create ? 1 : 0

  name     = var.resource_group.name
  location = var.resource_group.location
  tags     = var.tags
}

data "azurerm_resource_group" "existing" {
  count = var.resource_group.create ? 0 : 1
  name  = var.resource_group.name
}

locals {
  resource_group_name = var.resource_group.create ? azurerm_resource_group.this[0].name : data.azurerm_resource_group.existing[0].name
}

module "waf" {
  source   = "./modules/waf-policy"
  for_each = var.waf_policies

  resource_group_name = local.resource_group_name
  policy              = each.value
  tags                = var.tags
}

module "front_door" {
  source = "./modules/front-door"

  resource_group_name = local.resource_group_name
  config              = var.front_door
  waf_policies = {
    for key, policy in module.waf : key => {
      id                   = policy.id
      security_policy_name = var.waf_policies[key].security_policy_name
    }
  }
  tags = var.tags
}
