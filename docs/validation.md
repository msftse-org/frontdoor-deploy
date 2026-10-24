# Validation record

## Toolchain and scope

Validation performed on **23 October 2026 (Israel time)** with **Terraform 1.17.0** and **AzureRM 5.10.0**. Local execution used macOS ARM64; the private state-migration runner used Linux AMD64. The committed provider lock covers both platforms.

The live deployments used this repository's root and modules with isolated, disposable Azure Web Apps. Application code and test infrastructure are not part of the customer repository. No customer application was modified. The first deployment used the actual single-app example with only customer values replaced; a subsequent apply expanded the same deployment through its configuration inputs.

## Live acceptance of the Detection-default release

Terraform source revision **`2f2a1c711aa790bff9cacdbb77ae780ea43010e2`** was freshly cloned and deployed in the authorized Azure test subscription. All 18 Terraform source files matched the delivered repository. Subsequent handover edits update documentation only; the tested Terraform source is unchanged. Only temporary customer input values and separate disposable app fixtures were supplied; no customer application was modified. Custom DNS, domains and certificates are outside this test scope.

| Customer operation | Azure result |
| --- | --- |
| First deployment with omitted WAF mode | The actual single-app example created 8 resources. Azure reported Detection. The app returned the expected response through Private Link, including a test XSS query that was not blocked in Detection. |
| Initial application checks | All 6 baseline HTTP checks passed: private health, HTTPS redirection, uncached responses, and direct public denial on each of the three disposable apps. |
| Enable enforcement after tuning | The saved update plan changed the existing policy from Detection to explicit Prevention. Real custom-rule and managed-rule requests were subsequently blocked; the separate Detection endpoint continued allowing its test requests. |
| Expand the customer configuration | Additional origins, routes, endpoints, rule sets and WAF policy produced 31 managed edge resources. All 32 feature HTTP checks listed below passed again against this release. |
| Azure configuration readback | 17 checks passed for identities/scoped RBAC, Private Link, health probes, priorities/weights, affinity, enabled/disabled resources, HTTPS, caching, WAF settings/exclusions and separate diagnostics ownership. Terraform managed no diagnostic settings; the subscription governance policy created its own setting, and the Terraform plan remained unchanged. |
| Failover and recovery | Stopping the disposable primary app selected the backup. Restarting it restored primary traffic; both transitions were observed through Front Door. |
| Change an origin connection region | Updating the primary origin from West Europe to North Europe planned replacement of that origin and updates to its seven dependent routes. The new private connection was explicitly approved. The obsolete West Europe connection was removed on the disposable app, leaving only the approved North Europe connection; the primary app responded through that connection after propagation, and the complete 32-check HTTP suite passed again. |
| Convergence | Plans after the initial deployment, expanded configuration and region change reported no changes. The separate app-fixture plan also reported no changes. |
| Removal | All 31 edge resources and 7 app/identity/vault fixtures from this run were removed. Both states were empty and both resource groups were independently confirmed absent. |

The earlier existing-resource-group and Blob-backend migration/locking tests remain applicable; those paths were not changed or rerun in this round. The current run adds live verification of the new default and its rollout, repeated feature checks on the current code, and a real connection-region update. This is evidence for the listed scenarios, not a guarantee for every input combination or an untested customer application's behavior.

## Earlier broad validation

| Area | Live evidence |
| --- | --- |
| New resource group | The single-app deployment created 8 managed resources. Six HTTP checks passed, including private health traffic, uncached requests, HTTPS redirection and denied direct app access. |
| Existing resource group | A second deployment created 7 managed resources, served the same private app with HTTP 200, and produced a no-change plan. Destroying those 7 resources left the existing group and app intact. |
| Configuration updates | An apply added 23 resources and updated 8 in place for additional endpoints, groups, origins, routes, rules and WAF configuration. Its follow-up plan reported no changes. |
| Azure readback | 17 assertions passed against Azure APIs: Premium tier, timeout, identities/RBAC, disabled resources, HTTPS forwarding/probes, priorities/weights, affinity settings, regions, cache options, WAF modes/exclusions/associations and diagnostics ownership. |
| Private state backend | Local-to-Blob migration, second-checkout state access, concurrent lock rejection, lock release, and return to local state all passed using Entra managed identity and a private Blob endpoint. The same lineage and all 8 resource IDs were preserved; subsequent plans proposed no changes. |
| Diagnostics ownership | The earlier run had no diagnostic settings; the latest release verifies independent governance ownership as recorded above. No Log Analytics workspace or Event Hub was deployed. |

### Final HTTP suite: 32 passed, 0 failed

The final run verified the following against Azure after configuration propagation:

- HTTPS health reaches private web app.
- HTTP redirects to HTTPS.
- Uncached application requests reach the origin.
- Direct public app blocked: api.
- Direct public app blocked: backup.
- Direct public app blocked: web.
- API route origin path removes the route prefix.
- URL rewrite preserves the unmatched suffix.
- Bare /api route reaches API.
- Origin path replaces the matched route prefix.
- Disabled specific route falls back to main route.
- Response header overwrite, append and delete.
- Request header overwrite, append and delete.
- Path condition and HTTPS redirect rule.
- WAF block, lowercase transform and custom body.
- WAF covers root, API and static paths.
- Disabled WAF rule does not block.
- WAF redirect action.
- WAF custom body inspection.
- WAF negated header condition blocks wrong value.
- Managed rules block XSS query.
- Managed rules inspect JSON request body.
- WAF Allow custom rule precedence.
- WAF Log action continues managed evaluation.
- Policy-level exclusion limits inspected query arguments.
- Detection policy evaluates without blocking.
- Origin group session affinity cookie.
- Static caching, query separation and compression.
- Cache query mode ignore.
- Cache query mode include.
- Cache query mode exclude.
- Rate-limit custom rule enforces a burst.

The API recipe was checked end to end: `/api/inspect` arrived as `/inspect`. The rewrite example sent `/rewrite/inspect` as `/changed/inspect`. A configured `/internal` origin path replaced the matched route prefix.


The controlled outage test stopped the disposable primary app. Front Door served the backup through its North Europe private connection after approximately **81 seconds**. Restarting the primary restored primary responses after approximately **82 seconds**. These are observations from this test, not a recovery-time guarantee. Both apps were in West Europe; the test proves priority failover and two Private Link regions, not a regional application disaster-recovery exercise.

## Customer-readiness recheck

A second review on **23 October 2026 (Israel time)** repeated the first deployment from a fresh private GitHub checkout. It used the actual single-app example with only customer values replaced, the documented locked initialization, interactive `terraform apply`, exact private-connection approval, and `terraform output endpoint_urls`.

| Recheck | Result |
| --- | --- |
| Fresh onboarding | 8 Front Door/WAF resources created, with a no-change plan after apply |
| Public/private coexistence | Front Door returned the expected app response over its configured private origin while the app's explicitly enabled public path also returned 200; HTTP redirected to HTTPS and the managed WAF blocked an XSS test query |
| Final private configuration | The disposable app's authoritative Terraform changed public access to Disabled. Front Door still returned the expected app response, direct public access returned 403, HTTPS redirection and WAF blocking still passed. All 8 traffic checks across the two phases passed. |
| Azure configuration | 10 independent readback checks passed, including approved Private Link, target app, TLS checks, identity, HTTPS, disabled caching and absent diagnostics |
| Infrastructure convergence | Both Front Door and app-fixture plans reported no changes after cutover |
| Broader feature evidence | All 18 Terraform source files matched the files used for the earlier 32-check live suite, failover and backend tests; those successful evidence records were rechecked |
| Customer recipes | Eight HCL snippets extracted from the configuration guide passed separate mock plans: add-app, replica, prefix removal, rewrite, managed exclusion, custom WAF/rate rules, custom domain and Key Vault certificate reference. These plan checks do not validate DNS or retrieve certificates. |
| Documentation and packaging | 22 shell blocks passed syntax checking, 42 local links/anchors resolved and 25 public reference links returned HTTP 200. README/guide layouts and the embedded diagram were visually reviewed. State, real inputs, plans and test fixtures are excluded from the customer package. |
| Cleanup | The 8 Front Door resources and 3 disposable app fixtures from this recheck were removed. Both new states were empty, and all four temporary resource groups across both validation rounds were independently confirmed absent. Total removed across both rounds: 76 managed resources. |

The initial App Service/Private Link path is ready for customer onboarding. The customer still supplies its own names, app identifiers and working health path, approves its private connection, verifies its real application/login flows and owns the public-access cutover. Optional custom domains/certificates retain the limits below.

## Detection-default update

The root and WAF module default to Detection. Both customer examples inherit this mode; customers explicitly select Prevention after reviewing externally exported WAF logs and tuning. The fresh acceptance run above verified the implicit default and the transition to Prevention. Earlier blocking tests used Prevention.

## Native Terraform checks

Formatting, locked initialization and validation passed. **16 native test runs passed**: 14 module/root mock tests plus a plan of each actual customer example. These include the Detection default at root and module level and an explicit Prevention override. The checks create no Azure resources and do not replace integration tests.

```sh
terraform fmt -check -recursive
terraform init -backend=false -lockfile=readonly
terraform validate
terraform test
terraform test -test-directory=tests/examples -var-file=examples/single-app/terraform.tfvars.example
cp examples/multiple-apps/terraform.tfvars.json.example .terraform/multiple-apps-test.tfvars.json
terraform test -test-directory=tests/examples -var-file=.terraform/multiple-apps-test.tfvars.json
```

The private repository also runs these checks in GitHub Actions on pushes to `main` and pull requests. Review the [validation workflow runs](https://github.com/msftse-org/frontdoor-deploy/actions/workflows/validate.yml) for the status of the code revision being deployed.

## Observations and cleanup

The final live checks verified the documented route-prefix and rewrite behavior after Azure configuration propagation. Application readiness was checked with real HTTP requests, separately from Terraform apply and no-change plans.

Cleanup completed: Terraform removed **31 main Front Door resources**, **7 resources in the reused-group test**, and **27 fixture resources** (65 total). All three Terraform states contain no resources, and both temporary resource groups were independently confirmed absent in Azure. The reused group/app were verified intact after removing their Front Door deployment, before their later intentional fixture cleanup.

## Limits and customer acceptance

- Custom-domain DNS, Azure-managed certificate issuance and customer Key Vault certificate retrieval were **not live-tested**; these optional features were deferred. The test verified identity attachment and scoped role assignment, which does not prove certificate retrieval.
- WAF exclusions at policy, group and individual-rule scope were accepted and read back from Azure. Runtime tests cover the specific requests recorded above, not every managed rule, match operator or possible application attack.
- Non-App-Service origin types and every possible configuration combination were not exercised. Customer applications still need suitable health paths, connection approval, correct authentication/redirect behavior, and realistic application tests.
- The Blob backend test used a privately connected managed-identity runner. An operator using Azure CLI authentication must have both data-plane RBAC and network reachability. A private container is not itself a private network endpoint.
- The separate diagnostics application owns Event Hub log delivery. That application's logging pipeline was not tested by this repository.

Start with the [deployment walkthrough](getting-started.md#deploy-in-five-steps). The generated Front Door hostname needs no customer DNS or certificate setup. Use [configuration recipes](configuration.md) for future changes and [shared-state instructions](remote-state.md) only when the team adopts a shared backend.
