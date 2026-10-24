# Front Door module

Creates a Premium profile, system identity, optional identity role grants, endpoints, private origin groups/origins, routes, rule sets/rules, optional domains and certificate references, and WAF domain associations. Does not own applications, DNS records, diagnostic settings, or log destinations.

Inputs: `resource_group_name`, strongly typed `config`, `waf_policies` (policy IDs plus security-policy names), and `tags`. See `variables.tf` for the schema and validation. Outputs in `outputs.tf` provide profile/identity IDs, endpoint hostnames, route IDs, domain tokens, and private targets.

Use with AzureRM >=5.10,<6 and Terraform >=1.17,<2. The consuming root supplies the provider and backend. All resource names are caller supplied. The root examples show the `config` object as `front_door`.

All origins are private and certificate-checked; all routes forward HTTPS and redirect HTTP. Each endpoint/domain must reference a WAF policy. Cert access roles are granted to the profile's system identity. The caller/origin owner must approve connections and disable origin public access. Private Link is not managed-identity origin authentication.
