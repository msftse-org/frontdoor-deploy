# Deployment walkthrough

Use this guide when you need more detail than the [README quick start](../README.md#quick-start).

## What you get with the starter example

| Setting | Starting configuration |
| --- | --- |
| Front Door | **Premium**, a global service, with one public endpoint |
| Region values | **West Europe** (`westeurope`) for the new resource group and the origin's Private Link connection |
| Application | One **existing** Web App; its location, code and App Service plan stay unchanged |
| Routing | All paths (`/*`) go to that app; HTTP redirects to HTTPS; origin traffic uses HTTPS |
| Health checks | HTTPS `GET /health`, every 60 seconds per probing location; replace the path if needed |
| WAF | **Detection** on all paths: inspects without blocking; DRS 2.1, Bot Manager 1.1 and body inspection |
| Caching | Off |
| Identity | System-assigned identity on Front Door; it does not authenticate Private Link requests to the app |
| Terraform state | Local on the deployment machine initially |

West Europe is written in the example, not a hidden module default. Keep both location values for a Web App in West Europe. Front Door itself is global; neither field relocates the app. See [region settings](reference.md#deployment-and-profile) before changing an existing deployment.

## How it works

![Front Door Premium architecture: WAF in Detection, public endpoint, routes and nested origins, Microsoft-managed private endpoints, and existing Web Apps. Blue shows the starter path; purple shows an optional API expansion. The app owner approves connections and disables public access after cutover.](diagrams/frontdoor-architecture.png)

A **route** selects an **origin group** (a pool of application destinations). Each **origin** identifies an existing app. Front Door manages its own private endpoint; it does not need to share a VNet with the Web App. The app owner approves the connection and controls the app's public access. See [Private Link behavior](https://learn.microsoft.com/en-us/azure/frontdoor/private-link).

## Deploy in five steps

### 1. Prepare

Install the tested versions: [Terraform **1.17.0**](https://releases.hashicorp.com/terraform/1.17.0/) and [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli). The repository locks AzureRM **5.10.0**. Clone or download the repo and open a terminal in its root folder, where `main.tf` is located. Commands below use Bash/zsh; you can also copy files in your editor.

Have these ready:

- **Azure access:** permission to deploy into the target resource group and create it if requested. The subscription administrator registers `Microsoft.Cdn` and `Microsoft.Network`; see [permissions](deployment.md#ownership-and-permissions).
- **Existing app:** its resource ID and actual default hostname, a plan supporting Private Endpoints, HTTPS-only enabled, and an unauthenticated health path returning **HTTP 200**. Use the production site, not a deployment slot.
- **App owner:** someone who can approve the private connection and manage public access. If the app already serves users publicly, follow the [staged cutover](deployment.md#lock-down-the-existing-app) before disabling that access.

### 2. Fill in your configuration

```sh
az login
cp examples/single-app/terraform.tfvars.example terraform.tfvars
```

Open **`terraform.tfvars`** and replace these values. Field paths below describe where a value sits inside the file; they are not new lines to paste.

| Replace | Where in the file | Where to get the value |
| --- | --- | --- |
| Zero subscription UUID | `subscription_id` | Target Azure subscription ID |
| Example names and tags | `resource_group.name`, the other `name` fields, `security_policy_name`, `request_message`, `tags` | Customer naming convention; endpoint name must be available, WAF name alphanumeric |
| App hostname | `front_door.origin_groups.web.origins.primary.host_name` | Web App → Overview → Default domain; no `https://` or path |
| App resource ID | The same origin's `private_link.target_resource_id` | Web App → Properties → Resource ID |
| Health path | `front_door.origin_groups.web.health_probe.path` | App owner's working readiness path; keep `/health` only if it exists |

**Keep these starting settings unless you need something different:** both `location = "westeurope"` values, `resource_group.create = true`, the `/*` route, and WAF Detection. To use an existing resource group, enter its name and set `create = false`.

Keep map keys such as `public`, `web` and `primary` stable: Terraform uses them to track resources. You do not need to edit `.tf` files or `modules/` for onboarding. Terraform loads `terraform.tfvars` automatically. Use a separate checkout and state for each environment.

### 3. Review and deploy

```sh
terraform init -lockfile=readonly
terraform apply
```

Read the displayed plan, check the subscription, names and app target, then type **`yes`**. The unmodified single-app topology creates **8 resources** with a new resource group, or **7** when reusing a group. Stop if the plan includes unexpected deletion or replacement.

**Expected result:** apply completes and prints outputs. Terraform creates local state automatically; protect it and keep backups. The app connection still needs approval. No custom DNS, certificate or Blob backend setup is required for this first deployment.

### 4. Approve the private connection

The app owner opens **Azure Portal → existing Web App → Networking → private endpoint connections**. Review the pending request for this deployment and approve that specific connection. Confirm its status is **Approved**. See [approval details](deployment.md#approve-the-exact-private-connection) if needed.

Allow time for the connection and Front Door configuration to propagate. A successful apply does not mean application traffic is immediately ready; avoid repeatedly changing configuration while waiting.

### 5. Check that it works

```sh
terraform output endpoint_urls
```

Open the **`public`** URL from the output. Azure generates the hostname; use that URL rather than constructing one from the resource name.

| Check | Expected result |
| --- | --- |
| Open the health path through Front Door | HTTP 200 from the expected app |
| Test normal pages, login and API calls | The application works as expected |
| Open the HTTP version of the URL | Redirects to HTTPS |
| After the app owner disables public access, test the app's direct hostname from the internet | Access denied, while Front Door continues working |

Finally, run:

```sh
terraform plan
```

**Expected result: `No changes`.** Initial connectivity is verified when the checks above pass. Keep the environment's `terraform.tfvars` and state protected; neither belongs in a public repository. If something fails, use [troubleshooting](deployment.md#troubleshooting-and-removal).

## Enable WAF blocking after tuning

WAF starts in **Detection**, so it does not block attacks. **All paths (`/*`)** describes where inspection applies; it does not mean every request is blocked.

1. Confirm WAF logs are available to the team responsible for monitoring.
2. Test normal application traffic and tune narrow exclusions for verified false positives.
3. Add this field **inside the existing `waf_policies.default` object**, then run `terraform apply`:

```hcl
mode = "Prevention"
```

Verify normal traffic and the [controlled blocking test](configuration.md#waf-test-and-rate-limit-recipes). Continue monitoring. See [WAF modes and rules](configuration.md#waf-policies) for details.

## Which files do I use?

| File or folder | Purpose | Customer action |
| --- | --- | --- |
| `terraform.tfvars` | Your environment configuration | **Edit this** for names, apps, routes, regions and WAF |
| `examples/` | Starting configuration and optional examples | Copy the single-app example once; use others as references |
| `main.tf` | Connects the resource group and reusable modules | Keep for normal deployments |
| `variables.tf` / `outputs.tf` | Allowed inputs and deployment results | Consult when needed |
| `providers.tf`, `versions.tf`, `.terraform.lock.hcl` | Tested provider setup and versions | Keep; upgrade deliberately |
| `modules/front-door/` | Profile, endpoints, origins, routes, rules, domains and WAF associations | Reusable implementation |
| `modules/waf-policy/` | Managed/custom WAF rules and exclusions | Reusable implementation |
| `terraform.tfstate` | Local record of deployed resources | Protect and back up; never edit manually or commit |
| `docs/` | Task-specific help and the illustrated guide | Open the relevant guide below |

