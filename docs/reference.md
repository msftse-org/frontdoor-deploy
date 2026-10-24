# Customer input reference

All paths below are inside the environment variable file. `<key>` means a customer-selected stable map key, such as `web`. **Required** means this repository has no default. Omit optional maps/lists when unused. Optional values set to `null` use Terraform's declared default when one exists. The authoritative types are [root variables](../variables.tf); the provider also validates Azure-specific enums, ranges, and naming rules during planning.

**Starter values versus defaults:** the single-app example explicitly selects `westeurope` for the resource group and Private Link, and `GET /health` for probes. Those values override or supply the inputs below. For example, the module’s omitted-probe defaults are `HEAD /`, while both region inputs are required. See the [starter summary](getting-started.md#what-you-get-with-the-starter-example).

## Deployment and profile

| Input | Default | Meaning |
| --- | --- | --- |
| `subscription_id` | Required | Subscription in which Front Door and WAF are deployed |
| `resource_group.name` | Required | Dedicated new or existing resource group |
| `resource_group.location` | Required | Group metadata region when creating a group; ignored when reusing one. **Front Door itself is global** |
| `resource_group.create` | `true` | Set false to look up an existing group |
| `tags` | `{}` | Tags on resources that support tags |
| `front_door.name` | Required | Profile resource name |
| `front_door.response_timeout_seconds` | `120` | Origin response timeout, seconds; provider range 16–240 |
| `front_door.user_assigned_identity_ids` | `[]` | Existing user-assigned identity resource IDs to attach, in addition to the always-present system identity |
| `front_door.identity_role_assignments.<key>.scope` | Required per assignment | Resource scope for the **system-assigned** profile identity |
| `front_door.identity_role_assignments.<key>.role_definition_name` | Required per assignment | Existing Azure role name; e.g. Key Vault Secrets User |

The tier is fixed to `Premium_AzureFrontDoor`. There is no diagnostics/logging input. Attaching an identity does not authenticate Private Link origin requests; see [identity scope](configuration.md#managed-identity-and-key-vault-certificates).

Changing the location of a managed resource group forces its replacement; it does not move Front Door or the existing apps. See the [AzureRM 5.10 resource-group contract](https://github.com/hashicorp/terraform-provider-azurerm/blob/v5.10.0/website/docs/r/resource_group.html.markdown).

## Endpoints

Prefix: `front_door.endpoints.<key>`. At least one endpoint is required.

| Field | Default | Meaning |
| --- | --- | --- |
| `name` | Required | Available endpoint resource name; Azure generates its actual hostname |
| `enabled` | `true` | Whether the endpoint accepts traffic |
| `waf_policy_key` | `"default"` | Key of a policy in root `waf_policies` |

## Origin groups and health

Prefix: `front_door.origin_groups.<key>`. A group represents interchangeable replicas of one application. Independent apps normally use separate groups.

| Field | Default | Meaning |
| --- | --- | --- |
| `name` | Required | Azure origin-group name |
| `session_affinity_enabled` | `false` | Cookie-based session affinity; only enable when required |
| `health_probe.path` | `"/"` | Absolute path that returns HTTP 200 |
| `health_probe.request_type` | `"HEAD"` | HEAD or GET |
| `health_probe.interval_in_seconds` | `60` | Probe interval per probing location, 1–255 seconds; not total global probe frequency |
| `load_balancing.sample_size` | `4` | Recent probe sample count considered for health |
| `load_balancing.successful_samples_required` | `3` | Required successes; cannot exceed sample size |
| `load_balancing.additional_latency_in_milliseconds` | `50` | Latency tolerance when selecting eligible origins |
| `origins` | Required | Map of origins; at least one must be enabled |

Probes always use HTTPS. A 302 login redirect or 401 is not a successful health probe. Priority and weight operate after origin eligibility/health selection; they are not a substitute for an application disaster-recovery design.

## Origins and regions

Prefix: `front_door.origin_groups.<group>.origins.<origin>`.

| Field | Default | Meaning |
| --- | --- | --- |
| `name` | Required | Origin resource name within the group |
| `host_name` | Required | DNS hostname without scheme, port, or path; use the app's real default hostname |
| `origin_host_header` | Same as `host_name` | Host header sent to the app; must be bound to that app |
| `https_port` | `443` | Origin TLS port |
| `enabled` | `true` | Eligibility for traffic; each group still requires one enabled origin |
| `priority` | `1` | 1–5, smaller numbers preferred; use 2 for standby |
| `weight` | `1000` | 1–1000, relative share among eligible origins at the same priority |
| `private_link.target_resource_id` | Required | Full existing Azure resource ID; App Service production site, not slot |
| `private_link.target_type` | Unset | **Set `"sites"` for App Service**; service-specific subresource for other supported targets; omit for Private Link Service |
| `private_link.location` | Required | Supported Front Door Private Link region near this origin, independent of resource-group location |
| `private_link.request_message` | `"Front Door Premium private origin connection"` | 1–140 characters describing the request; include profile/application context |

Every origin must use Private Link and certificate-name validation. Forwarding uses HTTPS only; the provider's HTTP port is not used for origin traffic. Changing `private_link.location` replaces the Front Door origin with AzureRM 5.10.0 and can update dependent routes; approve the new private connection before expecting traffic. Changing the target can also require approval. See the [provider contract](https://github.com/hashicorp/terraform-provider-azurerm/blob/v5.10.0/website/docs/r/cdn_frontdoor_origin.html.markdown). See the [regional rollout procedure](customer-runbook.md#add-or-change-an-application-region-safely).

## Routes

Prefix: `front_door.routes.<key>`. At least one route is required.

| Field | Default | Meaning |
| --- | --- | --- |
| `name` | Required | Route resource name |
| `endpoint_key` | Required | Existing key from `front_door.endpoints` |
| `origin_group_key` | Required | Existing key from `front_door.origin_groups` |
| `patterns_to_match` | `["/*"]` | Absolute URL path patterns; `/api/*` does not include bare `/api` |
| `custom_domain_keys` | `[]` | Existing custom-domain keys exposed on this route |
| `rule_set_keys` | `[]` | Rule-set keys to attach; list position does not guarantee execution order |
| `link_to_default_domain` | `true` | Expose route on the generated azurefd.net hostname; false requires at least one custom domain |
| `enabled` | `true` | Whether this route serves traffic |
| `origin_path` | Unset | Replaces the matched route prefix; `/` removes it, `/internal` replaces it with `/internal` |
| `cache` | Unset (disabled) | Add the object below only for cacheable content |

HTTP and HTTPS are accepted; HTTP redirects to HTTPS, and origin forwarding stays HTTPS. Avoid conflicting patterns for the same host. More-specific matching routes win over less-specific ones. A route selects the entire group, not a hand-selected subset of origins.

When `cache` is present:

| Field under `cache` | Default | Meaning |
| --- | --- | --- |
| `query_string_caching_behavior` | `"UseQueryString"` | UseQueryString, IgnoreQueryString, IncludeSpecifiedQueryStrings, or IgnoreSpecifiedQueryStrings |
| `query_strings` | `[]` | Parameter names for IncludeSpecifiedQueryStrings/IgnoreSpecifiedQueryStrings |
| `compression_enabled` | `false` | Enable compression for configured MIME types |
| `content_types_to_compress` | `[]` | MIME types, e.g. text/css and application/javascript |

Cache expiry follows supported origin response headers/default service behavior; this module does not expose a TTL-override action. Review cache behavior with the application owner.

## Custom domains and certificates

Prefix: `front_door.custom_domains.<key>`, optional map, default `{}`.

| Field | Default | Meaning |
| --- | --- | --- |
| `name` | Required | Azure custom-domain resource name |
| `host_name` | Required | Customer's DNS name, e.g. www.customer.example |
| `waf_policy_key` | `"default"` | WAF policy covering this domain on all paths |
| `dns_zone_id` | Unset | Existing Azure DNS zone association; **does not create DNS records** |
| `certificate_key` | Unset | Unset selects Azure-managed TLS; otherwise a key in `certificates` |

TLS minimum is 1.2. This module currently requires a customer certificate for wildcards and hostnames longer than 64 characters. The DNS owner publishes validation TXT and traffic CNAME/alias records; see [domain onboarding](configuration.md#rules-caching-and-domains).

Prefix: `front_door.certificates.<key>`, optional map, default `{}`.

| Field | Default | Meaning |
| --- | --- | --- |
| `name` | Required | Front Door secret resource name |
| `key_vault_certificate_id` | Required | Existing Key Vault certificate URI, not raw certificate contents; versionless for rotation |

## Rule sets and actions

Prefix: `front_door.rule_sets.<set>`, optional map, default `{}`. Each set requires `name` and `rules` (map). Rule-set and rule names must satisfy Azure's naming rules, including no hyphens. Attach a set to routes using `rule_set_keys`. AzureRM represents route associations as a set; place order-dependent rules within one set and use their `order` fields.

Prefix within a set: `rules.<rule>`.

| Field | Default | Meaning |
| --- | --- | --- |
| `name` | Required | Rule resource name |
| `order` | Required | Unique evaluation order within this set; 0 is unconditional |
| `behaviour_on_match` | `"Continue"` | Continue or Stop |
| `path_condition.operator` | Required if condition present | Provider request-path operator, e.g. BeginsWith or Equal |
| `path_condition.values` | Unset | Match values without leading slash; required by most operators |
| `path_condition.transforms` | `[]` | Supported normalization transforms such as Lowercase |
| `request_headers` / `response_headers` | `[]` | Lists of `{name, action, value}` header actions |
| Header `action` | `"Overwrite"` | Append, Overwrite, or Delete |
| Header `value` | Unset | Required for Append/Overwrite; omit for Delete |
| `url_rewrite.source_pattern` | Required if rewrite present | Prefix to rewrite in the path remaining after the route pattern |
| `url_rewrite.destination_path` | Required if rewrite present | Replacement path |
| `url_rewrite.preserve_unmatched_path` | `true` | Keep the remainder of the path |
| `url_redirect.redirect_type` | `"PermanentRedirect"` | Moved, Found, TemporaryRedirect, or PermanentRedirect |
| `url_redirect.destination_host_name` | Unset | Destination host; unset retains incoming host |
| `url_redirect.destination_path` | Unset | Destination path; unset retains incoming path |
| `url_redirect.query_string` | Unset | Replacement query string |
| `url_redirect.destination_fragment` | Unset | Destination fragment |

Redirect protocol is always HTTPS. Each rule needs 1–5 actions. Rewrite and redirect cannot coexist in one rule. These are the supported rule families; arbitrary device/geo/cookie conditions and other actions require an intentional module extension.

## WAF policies

Prefix: `waf_policies.<key>`. Every endpoint/domain must reference a defined policy. Policies stay enabled with request-body inspection enabled and cover `/*`.

| Field | Default | Meaning |
| --- | --- | --- |
| `name` | Required | Alphanumeric policy name, starts with a letter, up to 128 characters |
| `security_policy_name` | Required | Front Door association resource name |
| `mode` | `"Detection"` | Start with inspection without blocking; export WAF logs externally, tune, then explicitly select Prevention to enforce rules |
| `redirect_url` | Unset | Target URL when a custom rule uses Redirect |
| `custom_block_response_status_code` | `403` | Block response HTTP status |
| `custom_block_response_body` | Unset | Base64-encoded custom block body |
| `custom_rules` | `{}` | Map of customer rules, described below |
| `managed_rules` | DRS 2.1 + Bot Manager 1.1, both Block | Nonempty list; setting it replaces the complete default list |

Prefix: `waf_policies.<policy>.custom_rules.<rule>`.

| Field | Default | Meaning |
| --- | --- | --- |
| `name` | Required | Custom-rule name |
| `priority` | Required | Unique per policy, 1–1000; lower first |
| `type` | `"MatchRule"` | MatchRule or RateLimitRule |
| `action` | `"Block"` | Provider-supported action, e.g. Block, Allow, Log, Redirect; challenge actions depend on service support |
| `enabled` | `true` | Whether the rule is evaluated |
| `rate_limit_duration_in_minutes` | `1` | RateLimitRule only: 1 or 5 |
| `rate_limit_threshold` | `100` | RateLimitRule only: positive request threshold |
| `match_conditions` | Required | 1–10 conditions; all conditions must match |
| Condition `match_variable` | Required | e.g. RequestHeader, RequestUri, RemoteAddr |
| Condition `operator` | Required | e.g. Equal, Contains, IPMatch; valid choices depend on variable |
| Condition `match_values` | Required | Match values interpreted by the operator |
| Condition `selector` | Unset | e.g. header name for RequestHeader |
| Condition `negation_condition` | `false` | Invert condition result |
| Condition `transforms` | `[]` | Normalizations such as Lowercase |

An Allow custom rule can stop later managed-rule inspection. Prefer narrow exclusions for false positives. Rate limiting is distributed and is not a precise per-user quota service.

For IP rules, `RemoteAddr` evaluates the original client address from `X-Forwarded-For`; `SocketAddr` evaluates the source address seen by WAF. Choose according to the customer's trusted proxy topology. Challenge actions require their own service-compatibility and rollout review; the baseline does not enable them.

Each item in `managed_rules`:

| Field | Default | Meaning |
| --- | --- | --- |
| `type`, `version` | Required | Supported rule-set type and version |
| `action` | `"Block"` | Rule-set action |
| `exclusions` | `[]` | Rule-set-wide exclusions |
| `overrides` | `[]` | Rule-group overrides |
| Override `rule_group_name` | Required | Exact group name in selected version |
| Override `exclusions` | `[]` | Exclusions for this group |
| Override `rules` | `[]` | Individual rule overrides |
| Rule `rule_id` | Required | Exact rule ID |
| Rule `enabled` | `true` | Enable/disable this rule |
| Rule `action` | `"AnomalyScoring"` | Version-compatible action, e.g. AnomalyScoring/Log for DRS 2.x |
| Rule `exclusions` | `[]` | Narrow rule-specific exclusions |

At all three scopes, each exclusion requires `match_variable`, `operator`, and `selector`. See the [single-rule example](configuration.md#waf-policies). Confirm group/rule IDs against the chosen managed rule-set version before applying.

## Outputs and ownership

`terraform output endpoint_urls` prints HTTPS URLs for enabled endpoints with an enabled route linked to the generated hostname. Disabled endpoints and endpoints serving only custom domains are omitted.

`terraform output -json front_door` returns `profile_id`, `profile_resource_guid`, `identity_principal_id`, `endpoints` (IDs and generated hostnames), `route_ids`, `custom_domain_validation`, and `private_link_targets`. `terraform output -json waf_policy_ids` returns the policy map.

Use `profile_id` in the external diagnostics application. DNS records, app deployment/authentication, app identities, origin public-access settings, private-connection approval, and remote-state infrastructure have separate owners. See [the ownership table](deployment.md#ownership-and-permissions).
