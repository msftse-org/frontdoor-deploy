# Operations and maintenance

**Deploying for the first time? Follow the [deployment walkthrough](getting-started.md#deploy-in-five-steps).** This guide starts after deployment and covers changes, regional rollout, recovery and upgrades. You do not need to read it all before starting.

Keep using the same `terraform.tfvars` and state for this environment. Terraform loads that file automatically; routine changes do not require edits to `modules/`.

## Find the task you need

| Task | Go to |
| --- | --- |
| Add an app, route or WAF rule | [Everyday changes](#make-everyday-changes) and [configuration recipes](configuration.md) |
| Change an app or connection region | [Regional rollout](#add-or-change-an-application-region-safely) |
| Undo a change, recover state or retire the deployment | [Recovery and removal](#recover-roll-back-and-remove) |
| Check drift or upgrade versions | [Maintenance](#maintain-the-deployment) |
| Let another operator deploy | [Shared Blob state](remote-state.md) |
| Diagnose a failed deployment or request | [Troubleshooting](deployment.md#troubleshooting-and-removal) |

## Make everyday changes

Edit `terraform.tfvars`, then run:

```sh
terraform apply
```

Review the displayed plan and confirm with `yes` only when correct. Approve any new private connection and check both new and existing application paths. A final `terraform plan` should report no changes. Keep Terraform as the owner of Front Door and WAF configuration instead of editing those resources manually in Azure Portal.

For a process that requires a saved plan or a separate approval, the optional equivalent is:

```sh
terraform plan -out=deployment.tfplan
# Review the plan before executing the next command.
terraform apply deployment.tfplan
```

Applying a saved plan does not ask again. Discard old plans after changing inputs or after another operator applies.

| Customer wants to… | Change in `terraform.tfvars` | Follow-up |
| --- | --- | --- |
| Add an independent app/API | Add an origin group with its origin, then a route referencing the group | Approve new Private Link; test the new path and existing paths |
| Add another replica | Add an origin inside the existing group | Same app behavior/data; approve connection; choose priority/weight |
| Add active/passive failover | Set primary priority 1, standby priority 2 | Test controlled failure with the app team; health and data replication are prerequisites |
| Share traffic between replicas | Same priority; adjust weights | Weights apply among eligible healthy origins after latency selection, not guaranteed percentages |
| Change URL paths | Edit `routes.<key>.patterns_to_match` | Add both `/api` and `/api/*` if both are needed; check overlaps |
| Strip `/api/` before forwarding | Set `origin_path = "/"` on the API route | See [origin-path recipe](configuration.md#strip-a-route-prefix) |
| Change probes | Edit group `health_probe` | Confirm HTTP 200; interval and volume affect every origin in the group |
| Change WAF behavior | Edit selected `waf_policies.<key>` | Tune narrowly; Detection does not block attacks |
| Add customer DNS hostname | Add custom domain, validate DNS, attach to route | See [domain onboarding](configuration.md#rules-caching-and-domains) |
| Enable static caching | Add `cache` to only the static route | Verify cache keys/headers; keep personal and authenticated responses uncached |
| Change names/map keys | Review replacement plan; use `moved` blocks for key-only refactors | Never casually rename a profile or resource group in production |
| Change log delivery | Use the separate diagnostics application | No Terraform logging configuration exists here |

Complete add-app, failover, WAF, rewrite, and certificate snippets are in [configuration.md](configuration.md). Do not edit `modules/` for these operations. Module edits are needed only to introduce a feature beyond the exposed contract; validate and test those changes before upgrading customer deployments.

## Add or change an application region safely

1. Have the application team deploy a compatible replica in the new region and prepare its data, authentication, deployment access, and readiness endpoint.
2. Add a new origin with a **new stable key**, its actual hostname/resource ID, and its supported nearby `private_link.location`. Give it priority 2 while the original stays at priority 1. Apply and approve the new connection.
3. Validate the new app through a temporary test route and separate origin group if you need deterministic testing while the original remains preferred. A priority-2 origin in the production group will not normally receive traffic while a healthy priority-1 origin is available. Use the same target/region/port to share the managed connection where supported.
4. Change priorities to make the new region preferred, or use equal priorities for active/active. Apply, allow propagation, and validate real application behavior. Keep the old origin for rollback.
5. After the agreed observation period, remove temporary test routing and retire the old origin if desired. The app team decides when to delete its old app and data.

Changing only `resource_group.location` is not a region migration. Changing an existing origin's `private_link.location` replaces that Front Door origin in AzureRM 5.10.0 and updates dependent routes. It can interrupt traffic until the new connection is approved and configuration propagates; prefer the phased approach above for production.

## Recover, roll back, and remove

- **Wrong route/WAF change:** restore the previous reviewed configuration, generate a fresh plan, and apply it. Allow propagation again. Reusing an old saved plan is not a rollback strategy.
- **Interrupted apply:** keep the state; inspect Azure, rerun `terraform plan`, and reconcile. Do not delete state or recreate the profile to make Terraform forget an error. Use `force-unlock` only after proving that no operation still owns the lock.
- **Local machine loss:** restore the protected state backup before operating. Shared Blob state reduces this risk and provides locking; migrate before team use.
- **Removal:** coordinate with the DNS and diagnostics owners, review `terraform plan -destroy -out=destroy.tfplan`, then apply it only when intentionally retiring this environment. Keep state until deletion finishes. Existing apps remain owned by their own stack; any other resources placed in a resource group created by this stack must be moved or accounted for before deleting that group.

For troubleshooting, see [deployment.md](deployment.md#troubleshooting-and-removal). The [validation record](validation.md) distinguishes tested behavior from features requiring customer-specific tests.


## Maintain the deployment

| When | Operator action |
| --- | --- |
| After a configuration change | Run `terraform apply`, review and confirm its plan, check affected routes, and confirm a no-change plan |
| During normal operation | Use the separately owned diagnostics application for availability, origin health and WAF alerts; a Terraform plan does not check service health |
| Before a second operator starts | Migrate the authoritative local state using [the Blob state guide](remote-state.md), then share the same configuration and code version |
| On a periodic configuration review | Run a plan to detect drift; investigate unexpected changes before applying. Review WAF false positives with the application and diagnostics owners |
| Before upgrading Terraform/provider/module code | Test in a separate non-production environment, review release notes, validate and review the resulting plan before production |
| Before changing DNS, certificates or retiring an origin | Coordinate with the app/DNS owners and use the relevant [configuration recipe](configuration.md) |

For provider upgrades, the root constraint currently permits AzureRM `5.10.x`. Change the version constraints deliberately if adopting a different minor/major version; keep root and module constraints compatible. Run `terraform init -upgrade` only as part of that planned upgrade, review and commit `.terraform.lock.hcl`, then run validation, mock tests and a non-production plan. Normal deployments use `terraform init -lockfile=readonly`. The CI actions are pinned to full commit IDs; review their official release notes when upgrading, update the commit and version comment together, and confirm the validation workflow passes.

When adopting the Detection default on an existing deployment, an omitted `mode` will plan a change to Detection. Set `mode = "Prevention"` explicitly before upgrading if that environment must retain enforcement.

Keep the reusable code and lock file in the customer's Git repository. Keep the authoritative environment configuration in the customer's controlled configuration store; it is ignored by this template. Protect local state/backups while local state is in use. Do not replace or recopy a deployed environment's `terraform.tfvars` from the example during upgrades: it contains that environment's settings.
