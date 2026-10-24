# WAF policy module

Creates one enabled Front Door Premium WAF policy with body inspection. Inputs are `resource_group_name`, strongly typed `policy`, and `tags`; output is `id`.

Defaults: Detection (inspection without blocking), Microsoft Default Rule Set 2.1, and Bot Manager 1.1. Custom rules support match and rate-limit types with unique priorities. Managed rules support nested group/rule overrides and exclusions. Enable WAF log delivery through the separate diagnostics application, tune false positives, then explicitly set `mode = "Prevention"` to enforce rules. Existing deployments that omit `mode` inherit Detection on upgrade; explicitly retain Prevention if already enforcing. Rule-set replacement is explicit; a nonempty managed rule list is required.

`security_policy_name` travels with the policy configuration for composition; the front-door module creates that association. This module creates no diagnostics or associations itself. See `variables.tf`, `main.tf`, and the root configuration guide for details.
