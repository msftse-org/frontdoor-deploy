variable "resource_group_name" {
  description = "Existing resource group for this module."
  type        = string
}

variable "tags" {
  description = "Customer ownership, environment, and cost allocation tags."
  type        = map(string)
  default     = {}
}

variable "policy" {
  description = "Premium WAF rules and settings. Exclusion scopes may be policy, group, or individual rule."
  type = object({
    name                              = string
    security_policy_name              = string
    mode                              = optional(string, "Detection")
    redirect_url                      = optional(string)
    custom_block_response_status_code = optional(number, 403)
    custom_block_response_body        = optional(string)
    custom_rules = optional(map(object({
      name                           = string
      priority                       = number
      type                           = optional(string, "MatchRule")
      action                         = optional(string, "Block")
      enabled                        = optional(bool, true)
      rate_limit_duration_in_minutes = optional(number, 1)
      rate_limit_threshold           = optional(number, 100)
      match_conditions = list(object({
        match_variable     = string
        operator           = string
        match_values       = list(string)
        selector           = optional(string)
        negation_condition = optional(bool, false)
        transforms         = optional(list(string), [])
      }))
    })), {})
    managed_rules = optional(list(object({
      type    = string
      version = string
      action  = optional(string, "Block")
      exclusions = optional(list(object({
        match_variable = string
        operator       = string
        selector       = string
      })), [])
      overrides = optional(list(object({
        rule_group_name = string
        exclusions = optional(list(object({
          match_variable = string
          operator       = string
          selector       = string
        })), [])
        rules = optional(list(object({
          rule_id = string
          enabled = optional(bool, true)
          action  = optional(string, "AnomalyScoring")
          exclusions = optional(list(object({
            match_variable = string
            operator       = string
            selector       = string
          })), [])
        })), [])
      })), [])
      })), [
      { type = "Microsoft_DefaultRuleSet", version = "2.1", action = "Block" },
      { type = "Microsoft_BotManagerRuleSet", version = "1.1", action = "Block" }
    ])
  })

  validation {
    condition     = contains(["Prevention", "Detection"], var.policy.mode) && can(regex("^[A-Za-z][A-Za-z0-9]{0,127}$", var.policy.name))
    error_message = "WAF mode must be Prevention or Detection; name must start with a letter and contain only alphanumerics (max 128)."
  }
  validation {
    condition     = length(var.policy.managed_rules) > 0
    error_message = "At least one managed rule set is required for the security baseline."
  }
  validation {
    condition = length(distinct([for rule in var.policy.custom_rules : rule.priority])) == length(var.policy.custom_rules) && alltrue([
      for rule in var.policy.custom_rules : rule.priority >= 1 && rule.priority <= 1000 &&
      contains(["MatchRule", "RateLimitRule"], rule.type) &&
      length(rule.match_conditions) >= 1 && length(rule.match_conditions) <= 10 &&
      (rule.type != "RateLimitRule" || (rule.rate_limit_threshold > 0 && contains([1, 5], rule.rate_limit_duration_in_minutes)))
    ])
    error_message = "Custom rules need unique priorities 1–1000, valid types, 1–10 conditions and a positive rate threshold with duration 1 or 5 minutes."
  }
}
