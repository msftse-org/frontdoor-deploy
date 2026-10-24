# Run with either committed example as -var-file; CI checks both formats.
mock_provider "azurerm" {}

run "customer_configuration" {
  command = plan

  assert {
    condition     = length(module.front_door.route_ids) == length(var.front_door.routes)
    error_message = "Every configured route must be exposed by the composed Front Door module."
  }
  assert {
    condition     = length(module.front_door.private_link_targets) == sum([for group in var.front_door.origin_groups : length(group.origins)])
    error_message = "Every configured origin must have a private connection target."
  }
  assert {
    condition     = length(module.waf) == length(var.waf_policies)
    error_message = "Every configured WAF policy must be composed by the root module."
  }
}
