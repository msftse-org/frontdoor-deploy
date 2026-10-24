# Azure Front Door Premium with private origins

Deploy **Azure Front Door Premium and WAF** in front of your existing Azure Web Apps, using **Private Link** for the connection to each app. Customer names, regions, origins and routes are configured in **one file: `terraform.tfvars`**.

## What this deploys

The starter creates a resource group, a Front Door profile and public endpoint, a WAF policy, and routing to one existing Web App. All URL paths (`/*`) reach that app over HTTPS. Your existing app stays under the application team's management.

A **route** maps URL paths to an **origin group**; each **origin** in that group identifies an app destination. You can add separate groups for other apps or more origins for replicas.

## Architecture

![Front Door Premium architecture: WAF in Detection, public endpoint, routes and nested origins, Microsoft-managed private endpoints, and existing Web Apps. Blue shows the starter path; purple shows an optional API expansion. The app owner approves connections and disables public access after cutover.](docs/diagrams/frontdoor-architecture.png)

Blue shows the starter deployment; purple shows optional API expansion. [Open the full-size diagram](docs/diagrams/frontdoor-architecture.png).

## Starting configuration

| Setting | Starter value and your choice |
| --- | --- |
| Region | **West Europe** (`westeurope`) for the resource group and Private Link. Change these values if needed for your deployment; Front Door itself is global. |
| Resource group | Creates a new group. To reuse one, enter its name and set `resource_group.create = false`. |
| WAF | **Detection**: inspects all paths without blocking. Review WAF logs and tune before switching to Prevention. |
| State | Stored locally first. [Move to shared Blob state](docs/remote-state.md) before teammates manage the same deployment. |

The first deployment uses Azure's generated Front Door hostname. Custom domains, extra apps and advanced routing are optional later additions. Neither region setting moves the existing Web App.

## Quick start

### Install the tools

The tested toolchain is **Terraform 1.17.0** and **AzureRM 5.10.0**. Terraform installs the locked AzureRM provider during `terraform init`; install Terraform and Azure CLI on your machine first.

On **macOS with Homebrew**:

```sh
brew update
brew tap hashicorp/tap
brew install hashicorp/tap/terraform azure-cli
```

Homebrew installs the current release. For the exact tested Terraform version, use the [1.17.0 downloads](https://releases.hashicorp.com/terraform/1.17.0/). For Windows/Linux, follow the official [Terraform installation](https://developer.hashicorp.com/terraform/install) and [Azure CLI installation](https://learn.microsoft.com/cli/azure/install-azure-cli) instructions.

Confirm the tools are available:

```sh
terraform version
az version
```

Clone the repository with Git, then run the deployment commands from its root folder. You can also download and extract it instead.

```sh
git clone https://github.com/msftse-org/frontdoor-deploy.git
cd frontdoor-deploy
```

Before starting, confirm Azure deployment permissions, a Web App plan supporting Private Endpoints, HTTPS-only enabled, and a health path returning **HTTP 200 without login**. The app owner must be able to approve the private connection. See [prerequisites and permissions](docs/getting-started.md#1-prepare).

### 1. Sign in and create your configuration

```sh
az login
cp examples/single-app/terraform.tfvars.example terraform.tfvars
```

### 2. Fill in `terraform.tfvars`

Replace the example subscription ID, resource names and tags. Supply the existing app's **default hostname**, **full resource ID**, and **working health path**; keep `/health` only if the app serves it. Copy the hostname from Web App → Overview and the resource ID from Properties.

Keep the West Europe values if appropriate for your app. You do not need to edit `main.tf` or `modules/`. Keep map keys such as `web` and `primary` stable after deployment. [Field-by-field instructions →](docs/getting-started.md#2-fill-in-your-configuration)

### 3. Review and deploy

```sh
terraform init -lockfile=readonly
terraform apply
```

Check the displayed plan, then confirm with **`yes`**. The starter creates **8 resources** with a new group, or **7** when reusing one. Terraform automatically creates local state; protect it and keep backups. Use a separate checkout and state per environment.

### 4. Approve the private connection

In **Azure Portal → existing Web App → Networking → private endpoint connections**, review and approve this deployment's pending connection. Wait for **Approved** status and configuration propagation before testing. [Approval help →](docs/deployment.md#approve-the-exact-private-connection)

### 5. Verify the application

```sh
terraform output endpoint_urls
```

Open the **`public`** URL from the output. Confirm the health path returns HTTP 200, normal pages/login/API calls work, and HTTP redirects to HTTPS. Afterward, confirm Terraform reports **No changes**:

```sh
terraform plan
```

For an existing public app, follow the [cutover checklist](docs/deployment.md#lock-down-the-existing-app) before disabling direct public access. Verify Front Door still works afterward. WAF remains in Detection until you explicitly [switch to Prevention after tuning](docs/configuration.md#waf-policies).

## Make changes later

Edit the same **`terraform.tfvars`**, run **`terraform apply`**, review the plan, and test affected paths. Approve new private connections when adding apps. Preserve the environment's configuration and state when updating the repo.

- [Configuration recipes](docs/configuration.md) — add apps, routes, replicas, WAF rules or custom domains.
- [Input reference](docs/reference.md) — every setting and default.
- [Operations guide](docs/customer-runbook.md) — region changes, upgrades and recovery.

## Further help

[Detailed deployment walkthrough](docs/getting-started.md) · [Troubleshooting](docs/deployment.md#troubleshooting-and-removal) · [Validation results](docs/validation.md) · [Illustrated offline guide](docs/customer-guide.html)
