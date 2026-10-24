# Optional: move local state to Azure Blob Storage

This is an operational step after the Front Door deployment, not a dependency of the main project. Use a separate state-storage lifecycle so destroying Front Door cannot destroy its state backend.

## Prepare the destination

Ask the platform team to provide a StorageV2 account and private `tfstate` container. Use Entra ID authentication, TLS 1.2 or newer, HTTPS only, no anonymous blob access, disabled shared keys, blob versioning and soft delete. Restrict network access to approved operator/runner networks; for private endpoints, clients need the corresponding private DNS and network reachability. Do not make the container public to solve an authentication problem.

Example for an operator with rights to create storage and assign roles (replace every placeholder):

```sh
STATE_SUBSCRIPTION='<state-subscription-id>'
STATE_RG='<state-resource-group>'
STATE_LOCATION='<azure-region>'
STATE_ACCOUNT='<globally-unique-lowercase-storage-name>'
OPERATOR_OBJECT_ID='<your-entra-object-id>'
OPERATOR_PUBLIC_IP='<approved-public-ip>'

az group create --subscription "$STATE_SUBSCRIPTION" \
  --name "$STATE_RG" --location "$STATE_LOCATION"
az storage account create --subscription "$STATE_SUBSCRIPTION" \
  --resource-group "$STATE_RG" --name "$STATE_ACCOUNT" --location "$STATE_LOCATION" \
  --kind StorageV2 --sku Standard_LRS --https-only true --min-tls-version TLS1_2 \
  --allow-blob-public-access false --allow-shared-key-access false \
  --default-action Deny --bypass None
az storage account network-rule add --subscription "$STATE_SUBSCRIPTION" \
  --resource-group "$STATE_RG" --account-name "$STATE_ACCOUNT" \
  --ip-address "$OPERATOR_PUBLIC_IP"
STATE_ACCOUNT_ID=$(az storage account show --subscription "$STATE_SUBSCRIPTION" \
  --resource-group "$STATE_RG" --name "$STATE_ACCOUNT" --query id --output tsv)
az role assignment create --subscription "$STATE_SUBSCRIPTION" \
  --assignee-object-id "$OPERATOR_OBJECT_ID" --assignee-principal-type User \
  --role 'Storage Blob Data Contributor' --scope "$STATE_ACCOUNT_ID"
# Wait for RBAC propagation, then use the correct tenant/subscription for data-plane login.
az account set --subscription "$STATE_SUBSCRIPTION"
az storage container create --account-name "$STATE_ACCOUNT" \
  --name tfstate --auth-mode login --public-access off
az storage account blob-service-properties update --subscription "$STATE_SUBSCRIPTION" \
  --resource-group "$STATE_RG" --account-name "$STATE_ACCOUNT" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 30 \
  --enable-container-delete-retention true --container-delete-retention-days 30
```

For production, select replication/retention according to recovery requirements. Grant teammates and CI identities `Storage Blob Data Contributor` at the container scope (`<account-id>/blobServices/default/containers/tfstate`) rather than distributing storage keys. Backend permission is separate from Azure resource deployment permission. Contributors to the state can read sensitive values stored in it.

## Migrate the authoritative local state

1. Freeze applies by all operators. Identify the authoritative local state and confirm `terraform workspace show` is `default`. This guide assumes one deployment per working directory and the default workspace. If you use additional workspaces, inventory and migrate each before resuming work.
2. Make a protected backup outside the repository. Replace `/secure/backup` below with an existing protected backup directory on your machine:

   ```sh
   umask 077
   terraform state pull > /secure/backup/frontdoor-before-migration.tfstate
   terraform state list > /secure/backup/frontdoor-before-migration-addresses.txt
   ```

3. Copy `backend.tf.example` to `backend.tf`. Copy `examples/remote.backend.hcl.example` to `customer.backend.hcl` and enter the real account/container and a **unique key per customer and environment**. These files contain backend coordinates, not credentials. Review the destination to ensure it has no unrelated state already stored at that key.
4. From the same initialized directory that owns the local state, run:

   ```sh
   terraform init -migrate-state -backend-config=customer.backend.hcl
   ```

   Read Terraform's migration prompt and confirm the intended source and destination. Do not use `-reconfigure` for the initial migration: it does not copy the existing state. Do not copy state by hand over an existing blob or use `-force-copy` to suppress review.

5. Verify before allowing anyone to apply:

   ```sh
   terraform state pull > /secure/backup/frontdoor-after-migration.tfstate
   terraform state list > /secure/backup/frontdoor-after-migration-addresses.txt
   diff /secure/backup/frontdoor-before-migration-addresses.txt /secure/backup/frontdoor-after-migration-addresses.txt
   terraform plan
   ```

   Confirm matching state lineage/resource IDs and expected serial progression, the blob exists at the selected key, and the plan proposes no infrastructure recreation. State snapshots are sensitive; keep backups in protected storage. Retire stale local state only after verifying the remote copy. Do not restore a stale backup into an active backend.

6. Distribute the same code version, lock file, backend block, nonsecret backend coordinates, and the **same authoritative environment variable file** through the customer's controlled configuration store. Sharing state does not synchronize `.tfvars`; different inputs can still propose unwanted changes to the shared environment. `backend.tf` is ignored in this template; each teammate must explicitly copy the example or the customer may choose to track the adopted backend block in their own repository. A fresh clone runs `terraform init -backend-config=customer.backend.hcl` (no migration), followed by `terraform plan`. Confirm remote state before planning. An initialized directory with obsolete backend metadata may use `-reconfigure` only after confirming it has no local state that still needs migration.

Azure Blob leases provide state locking. Keep locking enabled, serialize team applies, and use `-lock-timeout=5m` if needed. Never force-unlock an active run. Private networking and data-plane RBAC are required on every operator/CI machine.

For OIDC or managed-identity runners, replace the example's `use_cli=true` with the appropriate backend authentication settings (`use_oidc` or `use_msi`) and identity configuration. Backend authentication and provider authentication are separate. Avoid passing secrets in backend files or command-line arguments.

If migration fails, stop applies and inspect both state locations. Keep the source backup, determine which backend owns the latest state, fix access/networking, and retry the migration. Do not run `terraform apply` against an empty backend in an attempt to reconnect existing resources.

References: [AzureRM backend and identity/RBAC options](https://developer.hashicorp.com/terraform/language/backend/azurerm), [init migration behavior](https://developer.hashicorp.com/terraform/cli/commands/init).
