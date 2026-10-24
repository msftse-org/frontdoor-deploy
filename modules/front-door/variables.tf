variable "resource_group_name" {
  description = "Existing resource group for this module."
  type        = string
}

variable "tags" {
  description = "Customer ownership, environment, and cost allocation tags."
  type        = map(string)
  default     = {}
}

variable "config" {
  description = "Customer-supplied Front Door names and topology. Map keys are stable Terraform identities. All origins require Private Link."
  type = object({
    name                       = string
    response_timeout_seconds   = optional(number, 120)
    user_assigned_identity_ids = optional(set(string), [])
    identity_role_assignments = optional(map(object({
      scope                = string
      role_definition_name = string
    })), {})
    endpoints = map(object({
      name           = string
      enabled        = optional(bool, true)
      waf_policy_key = optional(string, "default")
    }))
    origin_groups = map(object({
      name                     = string
      session_affinity_enabled = optional(bool, false)
      health_probe = optional(object({
        path                = optional(string, "/")
        request_type        = optional(string, "HEAD")
        interval_in_seconds = optional(number, 60)
      }), {})
      load_balancing = optional(object({
        sample_size                        = optional(number, 4)
        successful_samples_required        = optional(number, 3)
        additional_latency_in_milliseconds = optional(number, 50)
      }), {})
      origins = map(object({
        name               = string
        host_name          = string
        origin_host_header = optional(string)
        https_port         = optional(number, 443)
        enabled            = optional(bool, true)
        priority           = optional(number, 1)
        weight             = optional(number, 1000)
        private_link = object({
          target_resource_id = string
          target_type        = optional(string)
          location           = string
          request_message    = optional(string, "Front Door Premium private origin connection")
        })
      }))
    }))
    routes = map(object({
      name                   = string
      endpoint_key           = string
      origin_group_key       = string
      patterns_to_match      = optional(list(string), ["/*"])
      custom_domain_keys     = optional(set(string), [])
      rule_set_keys          = optional(list(string), [])
      link_to_default_domain = optional(bool, true)
      enabled                = optional(bool, true)
      origin_path            = optional(string)
      cache = optional(object({
        query_string_caching_behavior = optional(string, "UseQueryString")
        query_strings                 = optional(list(string), [])
        compression_enabled           = optional(bool, false)
        content_types_to_compress     = optional(list(string), [])
      }))
    }))
    certificates = optional(map(object({
      name                     = string
      key_vault_certificate_id = string
    })), {})
    custom_domains = optional(map(object({
      name            = string
      host_name       = string
      waf_policy_key  = optional(string, "default")
      dns_zone_id     = optional(string)
      certificate_key = optional(string)
    })), {})
    rule_sets = optional(map(object({
      name = string
      rules = map(object({
        name               = string
        order              = number
        behaviour_on_match = optional(string, "Continue")
        response_headers = optional(list(object({
          name   = string
          action = optional(string, "Overwrite")
          value  = optional(string)
        })), [])
        request_headers = optional(list(object({
          name   = string
          action = optional(string, "Overwrite")
          value  = optional(string)
        })), [])
        url_rewrite = optional(object({
          source_pattern          = string
          destination_path        = string
          preserve_unmatched_path = optional(bool, true)
        }))
        url_redirect = optional(object({
          redirect_type         = optional(string, "PermanentRedirect")
          destination_host_name = optional(string)
          destination_path      = optional(string)
          query_string          = optional(string)
          destination_fragment  = optional(string)
        }))
        path_condition = optional(object({
          operator   = string
          values     = optional(list(string))
          transforms = optional(list(string), [])
        }))
      }))
    })), {})
  })

  validation {
    condition     = length(var.config.endpoints) > 0 && length(var.config.origin_groups) > 0 && length(var.config.routes) > 0
    error_message = "Provide at least one endpoint, origin group, and route."
  }
  validation {
    condition = alltrue([for group in var.config.origin_groups :
      length(group.origins) > 0 && anytrue([for origin in group.origins : origin.enabled])
    ])
    error_message = "Each origin group must have at least one enabled origin."
  }
  validation {
    condition = alltrue(flatten([for group_key, group in var.config.origin_groups : [
      for origin_key, origin in group.origins :
      !strcontains(group_key, "/") && !strcontains(origin_key, "/") &&
      can(regex("^[^/: ]+\\.[^/: ]+$", origin.host_name)) &&
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/", origin.private_link.target_resource_id)) &&
      !can(regex("(?i)/slots/", origin.private_link.target_resource_id)) &&
      origin.priority >= 1 && origin.priority <= 5 && origin.weight >= 1 && origin.weight <= 1000 &&
      length(origin.private_link.request_message) >= 1 && length(origin.private_link.request_message) <= 140
    ]]))
    error_message = "Origin keys cannot contain '/'; use a hostname without scheme/path, a full resource ID (no App Service slots), priority 1–5, weight 1–1000, and a 1–140 character Private Link message."
  }
  validation {
    condition = alltrue([for group in var.config.origin_groups :
      startswith(group.health_probe.path, "/") &&
      contains(["GET", "HEAD"], group.health_probe.request_type) &&
      group.health_probe.interval_in_seconds >= 1 && group.health_probe.interval_in_seconds <= 255 &&
      group.load_balancing.successful_samples_required <= group.load_balancing.sample_size
    ])
    error_message = "Health probes need an absolute path, GET/HEAD, interval 1–255, and successful_samples_required <= sample_size."
  }
  validation {
    condition = alltrue([for route in var.config.routes :
      contains(keys(var.config.endpoints), route.endpoint_key) &&
      contains(keys(var.config.origin_groups), route.origin_group_key) &&
      alltrue([for key in route.custom_domain_keys : contains(keys(var.config.custom_domains), key)]) &&
      alltrue([for key in route.rule_set_keys : contains(keys(var.config.rule_sets), key)]) &&
      (route.link_to_default_domain || length(route.custom_domain_keys) > 0) &&
      length(route.patterns_to_match) > 0 && alltrue([for pattern in route.patterns_to_match : startswith(pattern, "/")])
    ])
    error_message = "Routes must reference defined endpoints/groups/domains/rule sets, expose a domain, and use nonempty absolute path patterns."
  }
  validation {
    condition = alltrue([for domain in var.config.custom_domains :
      domain.certificate_key == null ? (!startswith(domain.host_name, "*.") && length(domain.host_name) <= 64) : contains(keys(var.config.certificates), domain.certificate_key)
    ])
    error_message = "Use a defined certificate_key for custom certificates. Wildcards and hostnames longer than 64 characters require a custom certificate."
  }
  validation {
    condition = alltrue(flatten([for rule_set in var.config.rule_sets : [for rule in rule_set.rules :
      !(rule.url_rewrite != null && rule.url_redirect != null) &&
      length(rule.response_headers) + length(rule.request_headers) + (rule.url_rewrite == null ? 0 : 1) + (rule.url_redirect == null ? 0 : 1) >= 1 &&
      length(rule.response_headers) + length(rule.request_headers) + (rule.url_rewrite == null ? 0 : 1) + (rule.url_redirect == null ? 0 : 1) <= 5 &&
      (rule.order != 0 || rule.path_condition == null) &&
      alltrue([for header in concat(rule.response_headers, rule.request_headers) :
        contains(["Append", "Overwrite", "Delete"], header.action) && (header.action == "Delete" ? header.value == null : header.value != null)
      ])
    ]]))
    error_message = "Rules require 1–5 actions, cannot combine rewrite/redirect, and order 0 cannot have conditions. Header values are required for Append/Overwrite and forbidden for Delete."
  }
  validation {
    condition = alltrue([for set_key, rule_set in var.config.rule_sets :
      !strcontains(set_key, "/") && alltrue([for rule_key in keys(rule_set.rules) : !strcontains(rule_key, "/")]) &&
      length(distinct([for rule in rule_set.rules : rule.order])) == length(rule_set.rules)
    ])
    error_message = "Rule orders must be unique within each rule set; rule-set and rule keys cannot contain '/'."
  }
}

variable "waf_policies" {
  description = "Policy IDs and customer security-policy names. Each domain is assigned exactly one policy."
  type = map(object({
    id                   = string
    security_policy_name = string
  }))
  validation {
    condition = alltrue(concat(
      [for endpoint in var.config.endpoints : contains(keys(var.waf_policies), endpoint.waf_policy_key)],
      [for domain in var.config.custom_domains : contains(keys(var.waf_policies), domain.waf_policy_key)]
    ))
    error_message = "Every endpoint and custom domain must reference an existing WAF policy key."
  }
}
