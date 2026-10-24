# Deployment help and troubleshooting

Follow the [deployment walkthrough](getting-started.md#deploy-in-five-steps) for the normal deployment. Use this page for [permissions](#ownership-and-permissions), [connection approval](#approve-the-exact-private-connection), [public-access cutover](#lock-down-the-existing-app), or [troubleshooting](#troubleshooting-and-removal).

## Ownership and permissions

| Component | Owner |
| --- | --- |
| Front Door profile, endpoint, origins, routes, rules, custom domains | This Terraform deployment |
| WAF policies and domain associations | This Terraform deployment |
| Existing App Service, app identity, public access configuration, app authorization | Existing application IaC/team |
| Approving the Front Door-managed Private Endpoint connection | Origin resource owner |
| DNS zone and ownership/traffic records | Customer DNS owner |
| Diagnostic settings and Event Hub forwarding | Separate diagnostics application |
| Remote state storage, networking, RBAC | Customer platform team |

The deployment principal needs resource permissions in the selected Front Door resource group, plus resource-group creation rights if `resource_group.create=true`. Using an existing group avoids needing subscription-wide creation permissions. The origin owner needs private-endpoint-connection approval permissions on the specific application. Optional role assignments additionally require `Microsoft.Authorization/roleAssignments/write` at their scopes. Do not grant subscription Owner merely to deploy this repository.

Register `Microsoft.Cdn`, `Microsoft.Network` (WAF), and the origin's resource provider beforehand. The provider uses `resource_provider_registrations="none"`; it will not attempt unrelated subscription registrations. Existing App Services normally already have `Microsoft.Web` registered.

## External diagnostics ownership

Diagnostic settings are managed separately from this Terraform deployment. Azure Policy may independently add a setting to Front Door. Keep that setting under its policy owner; coordinate with the platform team before the separate diagnostics application configures Event Hub delivery. Each setting should have one owner and a distinct name. Do not import policy-owned settings into this deployment.

This separation was verified in Azure: the governance policy created its own setting while the Front Door Terraform plan remained unchanged. See [Azure diagnostic settings](https://learn.microsoft.com/en-us/azure/azure-monitor/data-collection/diagnostic-settings).

## Collect origin information

Use the actual hostname returned by Azure; new App Service hostnames can contain regional suffixes.

```sh
az webapp show --ids '<full-app-resource-id>' \
  --query '{id:id,host:defaultHostName,publicAccess:publicNetworkAccess,httpsOnly:httpsOnly,plan:serverFarmId}'
```

Check the App Service plan supports Private Endpoints and select a Front Door-supported Private Link region close to the app. The resource-group location is independent of this region. Use the production site resource ID and `target_type="sites"`; Front Door does not support App Service deployment slots here.

The health probe must return HTTP 200 without interactive login. Prefer a lightweight readiness endpoint. Use GET if the application does not support HEAD. A root path that returns 302/401 is not a suitable probe. Front Door may send traffic even when all probes are unhealthy, so probe monitoring is still needed.

## Lock down the existing app

Set `public_network_access_enabled=false` and `https_only=true` in the app's authoritative IaC. Do not import the entire application into this repository just to change these properties. App Service supports public access and private endpoints at the same time. Public access restrictions apply to the public endpoint; they are not evaluated for traffic entering through a private endpoint. Private Link does not prove the application's public endpoint is disabled: an explicitly enabled public setting can leave a bypass around WAF.

For a new private-only app, disable public access before this deployment. For an existing public production app, agree a cutover window and use this explicit sequence:

1. Prepare and review the Terraform plan. Confirm the existing app's HTTPS setting, actual hostname and intended Private Link target. If existing users must retain public access during staging, have the app owner explicitly set `publicNetworkAccess=Enabled` in the app’s authoritative configuration before adding the private connection; preserve existing access restrictions. An unset value can switch the default public path to Disabled when a private endpoint exists.
2. Apply the plan, approve the exact private connection, and verify application traffic through the output Front Door hostname.
3. Validate the customer domain and certificate, test the application, and switch customer DNS to Front Door when ready. Account for DNS TTLs and old clients before removing public access.
4. Have the app owner set public access to Disabled in the app's authoritative IaC. Verify Front Door still serves the app and direct public requests are denied. Run `terraform plan` and review any changes before declaring cutover complete.

If the customer requires no public exposure at any time, use the private-only flow and arrange access/cutover accordingly. See [App Service public-access defaults](https://learn.microsoft.com/azure/app-service/overview-access-restrictions#app-access).

Changing `publicNetworkAccess` restarts Linux Web Apps; account for this in the cutover window. Disabling public access can affect SCM/Kudu and deployment agents. Ensure the app team has an appropriate private deployment path. Existing private endpoints can remain; this repository does not create a customer VNet or private DNS zone because Front Door provisions its managed private endpoint in Microsoft's network.

## Plan and apply

Use the standard Terraform commands in the README. The app owner confirms the actual hostname, supported plan, HTTPS-only setting, public-access setting and health path before deployment. Non-App-Service origins require a platform-specific review.

Azure CLI authentication is the default local experience. For CI, use workload identity federation/OIDC (`ARM_USE_OIDC`, `ARM_CLIENT_ID`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`) or a supported Azure-hosted managed identity. The repository's validation workflow deliberately needs no Azure credentials. Never store client secrets in `.tfvars`.

## Approve the exact private connection

After apply, list requests on each target:

```sh
az network private-endpoint-connection list --subscription '<origin-subscription-id>' --id '<app-resource-id>' \
  --query '[].{id:id,status:properties.privateLinkServiceConnectionState.status,message:properties.privateLinkServiceConnectionState.description}' \
  --output table
```

Inspect the request against the configured profile, origin, target, request message, and creation time. The message alone is not an authentication boundary. Approve the exact connection you reviewed, never all pending requests:

```sh
az network private-endpoint-connection approve \
  --subscription '<origin-subscription-id>' \
  --id '<reviewed-private-endpoint-connection-resource-id>' \
  --description 'Approved for the customer Front Door profile'
```

Repeat for distinct connections. Origins with the same target, subresource, and Private Link region can share one connection. Do not configure the same shared connection with different origin ports. Allow time for approval and edge configuration propagation.

A successful Terraform apply confirms control-plane provisioning, not immediate global traffic readiness. Microsoft's [Front Door FAQ](https://learn.microsoft.com/azure/frontdoor/front-door-faq#what-is-the-estimated-time-for-deploying-an-azure-front-door--does-my-front-door-remain-operational-during-the-update-process) documents up to 15 minutes for a single configuration operation and approximately 30 minutes for back-to-back changes. Avoid repeatedly editing routes while testing propagation; additional changes can extend the queue. Verify actual HTTP behavior before cutover.

## Verify and hand over

- `https://<endpoint-hostname>/` reaches the intended web app.
- `/api` and `/api/*` reach the API origin when configured.
- `http://<endpoint-hostname>/` redirects to HTTPS.
- Direct `https://<app-default-hostname>/` is blocked from the public internet.
- During Detection onboarding, a temporary WAF test rule produces a match in externally exported logs without blocking. After tuning and explicitly switching to Prevention, verify it blocks its test header/path; remove that rule afterward.
- Health probes return 200 and the external diagnostics application's Event Hub forwarding is healthy.
- A second `terraform plan` is empty after deployment convergence.

Test legitimate traffic before cutover. WAF `Allow` custom rules can terminate evaluation before managed rules; use them sparingly. Detection is the initial default for controlled tuning and does not block attacks. Enable external WAF log delivery, review and tune matches, then explicitly select Prevention and verify enforcement.

For an application using App Service authentication, verify forwarded-host handling and redirect URIs for the Front Door hostname. Private Link supplies network isolation; it does not replace application authentication or authorization.

## Troubleshooting and removal

| Symptom | What to inspect |
| --- | --- |
| Terraform errors before creating resources | Azure login/explicit subscription, RBAC, registered providers, available names, and the exact plan error |
| Endpoint 404, especially `CONFIG_NOCACHE` | Actual output hostname, enabled endpoint/route, `link_to_default_domain`, matching host/path, and propagation since the last change; this response alone does not prove propagation is the cause |
| 502/503 from Front Door | Exact Private Link request is Approved, app startup/probe, origin hostname/host header binding, correct target/region/port, TLS certificate chain/name |
| Front Door 403 | WAF test/rules versus app authorization; use the separate diagnostics application's request logs and Azure reference ID |
| Direct App Service 403 from public internet | Expected for the private baseline; verify management-plane publicNetworkAccess is explicitly Disabled too |
| Custom domain fails while default endpoint works | DNS ownership, certificate provisioning, CNAME/alias, domain association on the route, and its WAF association |
| API returns app 404 | Whether the backend expects `/api/...` or a stripped prefix; route pattern matching does not rewrite paths |
| Traffic still follows old configuration | Wait for the current deployment to propagate before submitting more updates; compare the Azure configuration with the reviewed Terraform configuration |

Read current configuration without changing it:

```sh
az afd endpoint show --subscription '<subscription-id>' --resource-group '<front-door-rg>' \
  --profile-name '<profile-name>' --endpoint-name '<endpoint-resource-name>'
az afd route list --subscription '<subscription-id>' --resource-group '<front-door-rg>' \
  --profile-name '<profile-name>' --endpoint-name '<endpoint-resource-name>'
az afd origin list --subscription '<subscription-id>' --resource-group '<front-door-rg>' \
  --profile-name '<profile-name>' --origin-group-name '<origin-group-resource-name>'
curl -sS -D - -o /dev/null 'https://<output-hostname>/<app-readiness-path>'
```

Retain timestamps and `X-Azure-Ref` for persistent errors. Do not turn off certificate checks or public-access restrictions to hide failures. Wait longer only when approval/configuration is correct and propagation is still plausible. Escalate persistent service errors with this evidence instead of repeatedly recreating the profile.

To remove an origin, first remove or redirect routes/rules that use its group. Apply, then remove the origin/group in a subsequent apply if Azure reports it is still referenced. For production teardown, the diagnostics application must remove its settings before deleting the profile; the origin team retains ownership of its apps. Destroying this root deployment does not destroy existing origin applications.
