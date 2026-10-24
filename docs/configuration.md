# Configuration recipes

**For the first deployment, use the [deployment walkthrough](getting-started.md#deploy-in-five-steps).** Come here when you want to add or change a feature. Edit the existing `terraform.tfvars`; the snippets below belong inside the named maps, not in new `.tf` files. Preserve the existing entries when adding another app or rule.

After each change: run `terraform apply`, review and confirm the plan, approve any new private connection, and test affected routes. Use the [operations guide](customer-runbook.md) for rollout and recovery, or the [input reference](reference.md) to look up every setting and default.

| Task | Recipe |
| --- | --- |
| Add another app or API | [Add an app](#add-a-web-app-or-origin) |
| Add a standby app | [Failover replica](#add-a-failover-replica) |
| Send `/api/orders` to the backend as `/orders` | [Strip a route prefix](#strip-a-route-prefix) |
| Rewrite a URL path | [Rewrite a path](#rewrite-a-path) |
| Tune WAF or verify blocking | [WAF policies](#waf-policies) / [test rules](#waf-test-and-rate-limit-recipes) |
| Add headers, caching or a hostname | [Rules, caching and domains](#rules-caching-and-domains) |
| Use a Key Vault certificate | [Identity and certificates](#managed-identity-and-key-vault-certificates) |

Use one environment input file: `terraform.tfvars`, or `terraform.tfvars.json` if you choose the multiple-app JSON example. Terraform replaces an entire map when a later input file assigns it; multiple files do not deep-merge app settings. The typed contract is in `variables.tf`; maintainers adding fields must also update the module contracts.

## Add a web app or origin

For a separate application, add an `origin_groups` entry containing its origins, then add a route whose `origin_group_key` references it. For replicas of the same application, add another origin to the existing group. Lower priority numbers are preferred; weight distributes traffic among eligible healthy origins with the same priority. Keep session affinity off unless the workload needs it.

```hcl
# Inside front_door.origin_groups:
api = {
  name = "og-api"
  health_probe = { path = "/health", request_type = "GET" }
  origins = {
    primary = {
      name      = "origin-api-primary"
      host_name = "customer-api.azurewebsites.net"
      private_link = {
        target_resource_id = "/subscriptions/.../resourceGroups/.../providers/Microsoft.Web/sites/customer-api"
        target_type        = "sites"
        location           = "westeurope"
      }
    }
  }
}
# Inside front_door.routes:
api = {
  name              = "route-api"
  endpoint_key      = "public"
  origin_group_key  = "api"
  patterns_to_match = ["/api", "/api/*"]
}
```

Patterns forward the original path by default: `/api/orders` remains `/api/orders`. For a route matching `/api/*`, set `origin_path = "/"` if the app expects `/orders`. A configured origin path replaces the matched route prefix: `/internal` sends `/api/orders` to `/internal/orders`. More-specific routes such as `/api/*` take precedence over `/*`; do not duplicate the same pattern for the same host/protocol. A route selects a whole origin group, not a subset of that group's origins.

For other supported private origins, supply that service's resource ID and `target_type`. The provider accepts types such as `blob`, `web`, `managedEnvironments`, and `Gateway`; exact platform support and regions must be checked for the chosen service. Omit `target_type` for a Private Link Service resource behind an internal load balancer. An externally owned Private Link Service must already exist before deploying this module and remain until the Front Door origins are removed.

## Add a failover replica

Add this entry alongside `primary` inside `front_door.origin_groups.web.origins`. Replace its hostname/resource ID with the existing regional replica. Keep the primary at priority 1. Both replicas must implement the same paths and authentication, with data replication handled by the app team.

```hcl
secondary = {
  name      = "origin-web-secondary"
  host_name = "replace-with-secondary-app.azurewebsites.net"
  priority  = 2
  weight    = 1000
  private_link = {
    target_resource_id = "/subscriptions/.../resourceGroups/.../providers/Microsoft.Web/sites/secondary-app"
    target_type        = "sites"
    location           = "northeurope"
    request_message    = "customer-profile: web secondary"
  }
}
```

Plan, review, apply, and approve the new connection before relying on failover. A healthy priority-1 origin normally keeps receiving traffic; test the standby through a temporary separate group/route or a controlled primary outage. For active/active, use equal priorities and choose relative weights. Equal weights do not guarantee an exact 50/50 split because health and latency also affect selection.

## Strip a route prefix

For the API route matching `["/api", "/api/*"]`, add this one field inside that route:

```hcl
origin_path = "/"
```

This sends `/api/orders` to the API as `/orders`. Leave `origin_path` unset when the app already serves `/api/orders`. Setting it to `/internal` instead sends that request to `/internal/orders`. The exact `/api` URL is also matched; verify the application's intended response for that URL. Health probes keep using the group's configured probe path.

## Rewrite a path

For a route matching `/*`, this rule sends `/rewrite/orders` to the same app as `/changed/orders`. Add the entry inside `front_door.rule_sets` and attach `rewrite_paths` to that route's `rule_set_keys`. Retain any existing rule-set keys used for headers or other behavior.

```hcl
rewrite_paths = {
  name = "RewritePaths"
  rules = {
    path = {
      name  = "RewritePath"
      order = 1
      path_condition = { operator = "BeginsWith", values = ["rewrite/"] }
      url_rewrite = {
        source_pattern          = "/rewrite/"
        destination_path        = "/changed/"
        preserve_unmatched_path = true
      }
    }
  }
}
```

Rewrite source matching uses the path remaining after the route pattern. Do not copy this source pattern onto a more-specific route and assume it sees the same path. Verify the URL received by the app. See [Microsoft's rewrite and origin-path behavior](https://learn.microsoft.com/azure/frontdoor/front-door-url-rewrite#source-pattern).

## Names and stable keys

The key `web` can remain stable while customer names follow any valid naming convention. Explicit names avoid hidden truncation/collision rules. Azure validates each resource's name constraints; in particular WAF policy names are alphanumeric, and rule/rule-set names cannot use hyphens. Use globally available endpoint names. Do not change keys casually; use Terraform `moved` blocks when reorganizing state.

## WAF policies

`waf_policies` is a map. Each endpoint and custom domain selects its policy via `waf_policy_key`, defaulting to `default`. Policies can be shared across domains or kept separate. All associated domains are protected on `/*`; path-specific exceptions belong in policy rules rather than unprotected associations.

**Coverage and enforcement are separate.** `/*` means inspect every URL on the associated endpoint/domain; it does not block all paths. The default `mode = "Detection"` evaluates without enforcement during onboarding; it does not block attacks. After reviewing external WAF logs and tuning false positives, set `mode = "Prevention"` to enforce configured rule actions. Add the `mode` field inside the existing `waf_policies.default` object, then plan and apply. Keep external WAF log delivery enabled when evaluating matches. DRS 2.1 uses anomaly scoring, so an individual match does not always cause a block.

The `custom_rules` map supports match and rate-limit rules, priorities, match conditions, selectors, transforms, and negation. Lower numeric priorities run earlier. Priorities must be unique per policy. Rate limits are distributed controls, not precise billing quotas.

`managed_rules` supports exclusions at rule-set, rule-group, and individual-rule scopes. Use the narrowest exception that fixes a verified false positive. Example of a single-rule exclusion:

```hcl
managed_rules = [
  {
    type = "Microsoft_DefaultRuleSet", version = "2.1", action = "Block"
    overrides = [{
      rule_group_name = "SQLI"
      rules = [{
        rule_id = "942200", enabled = true, action = "AnomalyScoring"
        exclusions = [{
          match_variable = "QueryStringArgNames", operator = "Equals", selector = "search"
        }]
      }]
    }]
  },
  { type = "Microsoft_BotManagerRuleSet", version = "1.1", action = "Block" }
]
```

Replacing `managed_rules` replaces the default list; include every rule set you want to retain. DRS 2.x individual overrides use `AnomalyScoring` or `Log`, while the rule-set action controls the final outcome. Validate rule IDs/group names against the chosen managed rule-set version. `custom_block_response_body`, if supplied, must be base64 encoded.

## WAF test and rate-limit recipes

Add these entries to `waf_policies.default.custom_rules` (merge into that map if it already exists). The first is a temporary deterministic block check; the second is an example starting point for customer-specific rate tuning. Choose unique priorities and thresholds appropriate for legitimate traffic.

```hcl
custom_rules = {
  deployment_test = {
    name     = "DeploymentTest"
    priority = 10
    action   = "Block"
    match_conditions = [{
      match_variable = "RequestHeader"
      selector       = "X-FrontDoor-Test"
      operator       = "Equal"
      match_values   = ["block"]
    }]
  }
  rate = {
    name                           = "RateLimit"
    priority                       = 100
    type                           = "RateLimitRule"
    action                         = "Block"
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = 1000
    match_conditions = [{
      match_variable = "RequestUri"
      operator       = "Contains"
      match_values   = ["/"]
    }]
  }
}
```

After deploying the temporary rule, make two requests to an otherwise working path. Replace the hostname and health path below:

```sh
curl -sS -o /dev/null -w '%{http_code}\n' 'https://<front-door-hostname>/health'
curl -sS -o /dev/null -w '%{http_code}\n' -H 'X-FrontDoor-Test: block' 'https://<front-door-hostname>/health'
```

With the default Detection mode, both requests should return HTTP 200 and the test-header match should appear in externally exported WAF logs; a configured Block action is not enforced in Detection. After tuning, explicitly set `mode = "Prevention"` in the policy and apply. With WAF in Prevention, expect HTTP 200 for the normal health request and HTTP 403 for the dedicated test header. Remove `deployment_test`, apply again and confirm both requests now succeed. A synthetic WAF test proves the association/blocking path, not that every managed rule fits the application. Tune actual false positives with the external diagnostics application's logs.

## Rules, caching, and domains

The multi-app example demonstrates response headers and static-only caching. Rules use `order`, `behaviour_on_match`, optional `path_condition`, request/response header actions, URL rewrite, or HTTPS redirect. Path-condition values omit the leading `/` as required by the provider. Order 0 is unconditional. A rule permits at most five actions, and cannot combine rewrite and redirect. Header deletion omits `value`.

`rule_set_keys` selects the rule sets attached to a route. AzureRM 5.10 stores these associations as a set, so list position does not guarantee execution order. Put order-dependent rules in one rule set and assign unique `order` values. See the [provider schema](https://github.com/hashicorp/terraform-provider-azurerm/blob/v5.10.0/internal/services/cdn/cdn_frontdoor_route_resource.go).

Cache configuration is opt-in; `UseQueryString` is the default cache-key strategy when enabled. Never cache login flows, sessions, authenticated APIs, or personalized pages without an application-specific design.

To add a custom domain, define `front_door.custom_domains`, then reference its key from the intended route's `custom_domain_keys`. Set `link_to_default_domain=false` when only the custom domain should serve the route. The default endpoint still has WAF coverage.

```hcl
custom_domains = {
  www = { name = "domain-www", host_name = "www.customer.example" }
}
```

Azure-managed certificates are the default. DNS is owned separately: create the `_dnsauth.<subdomain>` TXT record using `front_door.custom_domain_validation`, wait for approval/certificate issuance, and then point the CNAME to the **output endpoint hostname**. Do not guess that hostname. Domain onboarding can be staged: create the domain, publish the TXT record, then add it to routes after validation. `dns_zone_id` alone does not create DNS records. Apex domains require the DNS provider's appropriate alias/flattening solution. This module currently requires customer certificates for wildcard domains.

If Azure gates a follow-up operation while DNS validation is pending, the initial apply may not yet have produced root outputs. Retrieve the token from the domain in the Azure portal or with `az afd custom-domain show --subscription '<subscription-id>' --resource-group '<resource-group>' --profile-name '<profile-name>' --custom-domain-name '<domain-resource-name>' --query validationProperties.validationToken --output tsv`, publish the TXT record, and let provisioning converge. Re-plan after any interrupted apply; do not recreate the profile to resolve DNS validation.

## Remove a custom domain

First move its users/DNS to the intended replacement. Remove its key from every route’s `custom_domain_keys` and apply while keeping the domain entry in `front_door.custom_domains`. If it is a route’s last custom domain, either remove that route or deliberately enable its default hostname; do not enable another public hostname accidentally. After Azure confirms the routes are detached, remove the domain entry and apply again. Remove its certificate entry only when no remaining domain references it. This staged process avoids deleting a domain while Azure still associates it with a route.

## Managed identity and Key Vault certificates

The profile always has a system-assigned identity. `user_assigned_identity_ids` can additionally attach existing identities. Role assignments in `identity_role_assignments` target the **system-assigned** identity; attaching a user-assigned identity does not automatically grant it roles or select it for origin authentication.

```hcl
identity_role_assignments = {
  certificate_read = {
    scope                = "/subscriptions/.../resourceGroups/.../providers/Microsoft.KeyVault/vaults/customer-vault"
    role_definition_name = "Key Vault Secrets User"
  }
}
certificates = {
  web = {
    name                     = "secret-web-tls"
    key_vault_certificate_id = "https://customer-vault.vault.azure.net/certificates/web"
  }
}
custom_domains = {
  www = { name = "domain-www", host_name = "www.customer.example", certificate_key = "web" }
}
```

Use a supported certificate with its private key and chain in an existing Key Vault. The vault must use RBAC for the illustrated grant; access-policy vaults need their owner to grant access separately. Network policy must permit Front Door's supported certificate access path. RBAC propagation can delay secret creation, so pre-stage identity permissions if needed. A versionless certificate URI permits rotation. This example does not create a vault or certificate and does not move certificate contents into variables. Review [Microsoft's managed identity certificate guidance](https://learn.microsoft.com/azure/frontdoor/managed-identity).

Private Link origin traffic does not use this identity for bearer-token authentication. App-to-database/storage identities belong in application IaC.

## External diagnostics ownership

No diagnostics resource or diagnostics variable exists here. The separate diagnostics application consumes `front_door.profile_id`, configures its own `Microsoft.Insights/diagnosticSettings` child resource, and sends logs to Event Hub. Do not import its settings into this Terraform state. Removing this stack's profile removes the parent resource, so coordinate teardown with that application.
