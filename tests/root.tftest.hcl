mock_provider "azurerm" {}

run "customer_example_composition" {
  command = plan
  variables {
    subscription_id = "00000000-0000-0000-0000-000000000000"
    resource_group  = { name = "rg-test", location = "westeurope" }
    front_door      = jsondecode(file("examples/multiple-apps/terraform.tfvars.json.example")).front_door
    waf_policies    = jsondecode(file("examples/multiple-apps/terraform.tfvars.json.example")).waf_policies
  }
  assert {
    condition     = length(module.front_door.route_ids) == 3 && length(module.waf) == 1 && var.waf_policies["default"].mode == "Detection"
    error_message = "The customer example must compose the edge and WAF modules with Detection as its default mode."
  }
}

run "reuse_group_without_owning_it" {
  command = plan
  variables {
    subscription_id = "00000000-0000-0000-0000-000000000000"
    resource_group  = { name = "rg-existing", location = "westeurope", create = false }
    front_door      = jsondecode(file("examples/multiple-apps/terraform.tfvars.json.example")).front_door
    waf_policies    = jsondecode(file("examples/multiple-apps/terraform.tfvars.json.example")).waf_policies
  }
  assert {
    condition     = length(azurerm_resource_group.this) == 0 && length(data.azurerm_resource_group.existing) == 1
    error_message = "Reusing a group must read it without adding it to Terraform's managed resources."
  }
}

run "output_only_usable_default_endpoints" {
  command = plan
  variables {
    subscription_id = "00000000-0000-0000-0000-000000000000"
    resource_group  = { name = "rg-test", location = "westeurope" }
    waf_policies    = jsondecode(file("examples/multiple-apps/terraform.tfvars.json.example")).waf_policies
    front_door = merge(jsondecode(file("examples/multiple-apps/terraform.tfvars.json.example")).front_door, {
      endpoints = {
        public      = { name = "fde-test-public" }
        disabled    = { name = "fde-test-disabled", enabled = false }
        custom_only = { name = "fde-test-custom" }
        route_off   = { name = "fde-test-route-off" }
      }
      custom_domains = { www = { name = "domain-www", host_name = "www.example.com" } }
      routes = {
        web = {
          name = "web", endpoint_key = "public", origin_group_key = "web"
        }
        disabled_endpoint = {
          name = "disabled-endpoint", endpoint_key = "disabled", origin_group_key = "web"
        }
        custom = {
          name                   = "custom", endpoint_key = "custom_only", origin_group_key = "web"
          link_to_default_domain = false, custom_domain_keys = ["www"]
        }
        disabled_route = {
          name = "disabled-route", endpoint_key = "route_off", origin_group_key = "web", enabled = false
        }
      }
    })
  }
  assert {
    condition     = keys(output.endpoint_urls) == ["public"]
    error_message = "The customer URL output must omit disabled endpoints/routes and custom-domain-only routes."
  }
}
