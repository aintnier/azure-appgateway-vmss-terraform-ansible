[![Terraform CI](https://dev.azure.com/aintnier/azure-appgateway-vmss-terraform-ansible/_apis/build/status/ci-pipeline?branchName=main&label=Terraform%20CI)](https://dev.azure.com/aintnier/azure-appgateway-vmss-terraform-ansible/_build?definitionId=ci-pipeline)
[![Deploy](https://dev.azure.com/aintnier/azure-appgateway-vmss-terraform-ansible/_apis/build/status/deploy-pipeline?branchName=main&label=Deploy)](https://dev.azure.com/aintnier/azure-appgateway-vmss-terraform-ansible/_build?definitionId=deploy-pipeline)
[![Destroy](https://dev.azure.com/aintnier/azure-appgateway-vmss-terraform-ansible/_apis/build/status/destroy-pipeline?branchName=main&label=Destroy)](https://dev.azure.com/aintnier/azure-appgateway-vmss-terraform-ansible/_build?definitionId=destroy-pipeline)

[![Azure](https://img.shields.io/badge/Azure-Cloud-0078D4?logo=microsoft-azure)](https://azure.microsoft.com/)
[![Terraform](https://img.shields.io/badge/Terraform-1.14.8-7B42BC?logo=terraform)](https://www.terraform.io/)
[![Auth](https://img.shields.io/badge/Auth-OIDC%20Federated-green?logo=openid)](https://docs.microsoft.com/en-us/azure/active-directory/develop/workload-identity-federation)

# Azure AppGateway & VMSS - Terraform Lab

N-tier IaaS architecture on Azure featuring Application Gateway (L7), Standard Load Balancer (L4), dual Virtual Machine Scale Sets (Frontend + Backend), Ansible configuration management via cloud-init, and full governance guardrails - all managed via **Terraform** and orchestrated through **Azure DevOps CI/CD** pipelines with **OIDC authentication**.

---

## Architecture Overview

```
                    Internet
                       │
                       ▼
              ┌─────────────────┐
              │  Application    │   Public IP (HTTPS 443)
              │  Gateway WAF v2 │   TLS Termination
              │  (Basic Rule)   │   WAF Detection Mode
              └────────┬────────┘
                       │ HTTP 80
                       ▼
              ┌─────────────────┐
              │  VMSS Frontend  │   Nginx Reverse Proxy
              │  (snet-frontend)│   /  -> local HTML
              │  Autoscale 2–5  │   /api -> proxy_pass ──┐
              └─────────────────┘                        │
                                                         │ HTTP 80
                                                         ▼
                                                ┌─────────────────┐
                                                │  Standard LB    │
                                                │  (Internal L4)  │
                                                │  Private IP     │
                                                └────────┬────────┘
                                                         │ HTTP 80
                                                         ▼
                                                ┌─────────────────┐
                                                │  VMSS Backend   │
                                                │  (snet-backend) │
                                                │  Nginx API /api │
                                                └─────────────────┘

  ┌──────────────────────────────────────────────────────────────────────┐
  │  Supporting Services                                                 │
  │  • Azure Bastion (AzureBastionSubnet) - secure SSH, no public IPs    │
  │  • Key Vault - SSH keys, self-signed TLS certificate                 │
  │  • Log Analytics - AppGW access/WAF/performance logs                 │
  │  • Network Watcher - IP Flow Verify, Topology (portal)               │
  │  • Azure Load Testing - 500 req/s validation (JMeter)                │
  │  • Azure Policy - SKU restriction + location lock (westeurope)       │
  │  • Consumption Budget - 6€ with 50%/80% alerting                     │
  │  • Action Groups - email notifications on budget + autoscale         │
  └──────────────────────────────────────────────────────────────────────┘
```

### Traffic Flow (N-Tier Serial Traversal)

1. **Internet -> AppGW** - HTTPS 443, TLS termination via self-signed cert from Key Vault
2. **AppGW -> Frontend VMSS** - Basic routing rule, all traffic forwarded to `frontend-pool` (HTTP 80)
3. **Frontend Nginx** - Serves `/` locally (hostname page), reverse-proxies `/api` to Internal LB
4. **Internal LB -> Backend VMSS** - TCP port 80 load balancing across backend instances
5. **Backend Nginx** - Serves `/api` with API response page

---

## Skills Demonstrated

| Area                         | Detail                                                                                                                                                                         |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Azure Networking**         | Application Gateway WAF v2 (L7), Standard Internal Load Balancer (L4), NSG subnet isolation, path-based routing via Nginx reverse proxy                                        |
| **Compute & Scaling**        | VMSS with CPU-based autoscale rules, cloud-init OS bootstrap, dual-tier instance pools (Frontend + Backend)                                                                    |
| **Configuration Management** | Ansible Local-Pull via cloud-init `custom_data`, idempotent playbook with role-based templates (frontend/backend)                                                              |
| **Infrastructure as Code**   | Terraform flat-file layout (domain-split, no `main.tf`), remote state with locking, `locals {}` + `try()` dependency chains                                                    |
| **CI/CD & Automation**       | Azure DevOps multi-stage pipelines (CI, Deploy, Destroy), OIDC federated auth (zero static secrets), manual approval gates                                                     |
| **Security & Zero-Trust**    | Key Vault RBAC (managed identity for AppGW), WAF Detection mode (OWASP 3.2), Azure Bastion (no public IPs on VMs), NSG deny-all Internet                                       |
| **FinOps & Governance**      | Azure Policy (SKU + region restriction), Consumption Budget with Action Group alerts, standard tagging (`project`, `managed_by`, `environment`, `owner`, `ttl`, `cost-center`) |
| **Observability**            | Log Analytics Workspace, AppGW diagnostic settings (access/WAF/performance logs), Azure Monitor autoscale alerts, Network Watcher (IP Flow Verify, Topology)                   |
| **Load Testing**             | Azure Load Testing (IaC-provisioned), JMeter test plan (500 req/s, 10 min), P95 latency validation                                                                             |

---

## Cost Analysis

> Cost breakdown will be added after lab execution.

---

## Phase 0: Project Foundation

Before deploying the infrastructure, two foundation pieces must be established once via the Azure CLI and portal.

### Zero-Trust Authentication (OIDC)

This project does **not** use long-lived client secrets. Azure DevOps pipelines authenticate to Azure exclusively through **OpenID Connect (OIDC) Federated Identity**.

| Azure DevOps Object     | Type               | Description                                                                               |
| ----------------------- | ------------------ | ----------------------------------------------------------------------------------------- |
| `azure-oidc-connection` | Service Connection | ARM service connection using **Workload Identity Federation (OIDC)**. No client secret.   |
| `terraform-vars`        | Variable Group     | Variable group linked to the pipelines. Can hold overrides for Terraform variables.       |
| `dev`                   | Environment        | Deployment environment with **manual approval gate** configured for Apply/Destroy stages. |

<details>
<summary>Azure CLI App Registration commands</summary>

```bash
# Create App Registration
az ad app create --display-name "azdevops-appgw-vmss-lab"
az ad sp create --id <APP_ID>

# Assign Infrastructure Roles
az role assignment create --assignee <SP_ID> --role Contributor --scope /subscriptions/<SUB_ID>
az role assignment create --assignee <SP_ID> --role "Resource Policy Contributor" --scope /subscriptions/<SUB_ID>
az role assignment create --assignee <SP_ID> --role "Role Based Access Control Administrator" --scope /subscriptions/<SUB_ID>
```

</details>

![App Registration](docs/imgs/setup/01-azure-portal-app-registration-overview.png)
_Fig. 1: App Registration `azdevops-appgw-vmss-lab` overview._
<br>
![IAM Role Assignments](docs/imgs/setup/08-azure-portal-iam-role-assignments.png)
_Fig. 2: Infrastructure IAM role assignments granted to the Service Principal at the Subscription scope._
<br>
![OIDC Federated Credentials](docs/imgs/setup/07-azure-portal-federated-credential.png)
_Fig. 3: OIDC Federated Credential established to authorize Azure DevOps without long-lived secrets._

### Remote Terraform State

Terraform state is stored in a dedicated Azure Storage Account with state locking enabled:

| Storage Account          | Container | State Key                 |
| ------------------------ | --------- | ------------------------- |
| `stterraformstate080426` | `tfstate` | `appgateway-vmss.tfstate` |

<details>
<summary>Azure CLI setup commands</summary>

```bash
RESOURCE_GROUP="rg-terraform-state"
STORAGE_ACCOUNT="stterraformstate080426"
CONTAINER="tfstate"
LOCATION="westeurope"

az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION"

az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2

az storage container create \
  --name "$CONTAINER" \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode login
```

</details>

![Storage Containers](docs/imgs/setup/02-azure-portal-storage-container.png)
_Fig. 4: The `tfstate` Blob container ready to host the Terraform remote state._

> Update `infra/backend.tf` if you change the Storage Account name or Resource Group.

### Azure DevOps Setup

Once the App Registration is in place, the Azure DevOps project was configured to enable the pipeline execution.

1. **Environment (Approval Gates)**
   Created a `dev` environment with explicit "Approvals and checks" to prevent accidental `terraform apply` or `destroy` runs.
   ![Azure DevOps Environment](docs/imgs/setup/03-azure-devops-environment-dev.png)
   _Fig. 5: The `dev` Environment enforcing a manual approval gate._

2. **Variable Group**
   Created an empty `terraform-vars` variable group (with a placeholder variable) to safely inject parameters into the IaC workflow.
   ![Azure DevOps Variable Group](docs/imgs/setup/05-azure-devops-variable-group-saved.png)
   _Fig. 6: The `terraform-vars` Variable Group linked to the pipelines._

3. **Service Connection (OIDC)**
   Configured `azure-oidc-connection` using "Workload Identity federation (manual)". The `Issuer` and `Subject identifier` generated by Azure DevOps were then provisioned as a Federated Credential in the Entra ID App Registration to establish trust.
   ![Azure DevOps Service Connection](docs/imgs/setup/06-azure-devops-service-connection-oidc.png)
   _Fig. 7: The OIDC Service Connection fully established and validated._

### Continuous Integration (CI)

The Azure DevOps CI pipeline ([`ci-pipeline.yml`](pipelines/ci-pipeline.yml)) runs `terraform fmt -check` and `terraform validate` on every push and pull request to `main` - without contacting Azure state.

---

## CI/CD Workflows

Apply and destroy workflows are **manual by design** to prevent accidental infrastructure changes.

| Pipeline               | Trigger             | Stages                                                              |
| ---------------------- | ------------------- | ------------------------------------------------------------------- |
| `ci-pipeline.yml`      | Push / PR to `main` | `fmt -check` -> `validate`                                          |
| `deploy-pipeline.yml`  | Manual              | `plan` -> publish artifact -> manual approval -> `apply`            |
| `destroy-pipeline.yml` | Manual              | `plan -destroy` -> publish artifact -> manual approval -> `destroy` |

> You can find the pipeline definitions in the [`pipelines/`](pipelines/) directory.

Authentication uses **OIDC Federated Identity** on all pipelines. No static client secret is stored anywhere in the repository.

> ⚠️ **Never run `terraform plan`, `apply`, or `destroy` from the local terminal.** All operations are executed exclusively through CI/CD pipelines.

---

## Validation

> Validation screenshots and results will be added after lab execution.

---

## Key Technical Decisions

| Decision                                 | Rationale                                                                          |
| ---------------------------------------- | ---------------------------------------------------------------------------------- |
| **Basic Rule on AppGW** (not path-based) | Enforces true n-tier serial traversal: AppGW -> Frontend -> Internal LB -> Backend |
| **Nginx reverse-proxy on Frontend**      | Frontend VMSS handles path routing (`/api` -> proxy_pass to Internal LB)           |
| **Ansible Local Pull via cloud-init**    | Every VMSS instance self-configures at boot - works for autoscale events           |
| **Static IP on Internal LB**             | Predictable target for Nginx `proxy_pass` directive                                |
| **WAF in Detection mode**                | Prevents blocking synthetic load test traffic while still logging threats          |
| **OIDC (Workload Identity Federation)**  | No client secrets to rotate - modern, secure pipeline authentication               |

---

## Known Limitations

- **VM SKU availability in West Europe:** Certain VM SKUs (especially the `Standard_B` series) are not always available due to regional capacity constraints. If quota fails, switch the allowed SKUs to `Standard_D2s_v3` in `variables.tf` and the Azure Policy parameter.
- **Bastion & Application Gateway hourly cost:** Both resources generate significant hourly spend even at idle. The consumption budget and Action Group alerts mitigate surprise bills, but the `destroy` pipeline must be executed promptly after validation to contain costs.

---

## Repository Structure

```
.
├── infra/                     # Terraform configuration (flat, no modules)
│   ├── providers.tf           # Terraform & provider version pinning
│   ├── backend.tf             # Remote state backend (Azure Storage)
│   ├── variables.tf           # All variables + locals
│   ├── networking.tf          # RG, VNet, Subnets, NSGs, Public IPs
│   ├── keyvault.tf            # Key Vault, TLS cert, SSH key, managed identity
│   ├── appgateway.tf          # Application Gateway WAF v2
│   ├── loadbalancer.tf        # Internal Standard Load Balancer
│   ├── compute.tf             # Frontend & Backend VMSS + Autoscale
│   ├── bastion.tf             # Azure Bastion
│   ├── governance.tf          # Budget, Policies, Action Groups, Log Analytics
│   ├── network-watcher.tf     # Network Watcher
│   ├── loadtesting.tf         # Azure Load Testing resource
│   ├── outputs.tf             # All output values
│   └── scripts/
│       └── cloud-init.sh.tpl  # Cloud-init template (Ansible local-pull)
├── config/                    # Ansible configuration (source of truth)
│   ├── ansible.cfg            # Local-pull optimised settings
│   ├── playbook.yml           # Main playbook (frontend/backend roles)
│   └── templates/
│       ├── index.html.j2      # Frontend HTML (hostname display)
│       ├── api.html.j2        # Backend API HTML/JSON
│       ├── nginx-frontend.conf.j2  # Nginx reverse-proxy config
│       └── nginx-backend.conf.j2   # Nginx API server config
├── pipelines/                 # Azure DevOps CI/CD (OIDC)
│   ├── ci-pipeline.yml        # fmt-check + validate (PR/push)
│   ├── deploy-pipeline.yml    # plan -> approval -> apply
│   └── destroy-pipeline.yml   # plan -destroy -> approval -> destroy
├── tests/
│   └── loadtest.jmx           # JMeter test plan (500 req/s, 10 min)
├── docs/
│   └── imgs/                  # Validation screenshots
└── README.md
```

---

## Tech Stack

| Component      | Technology                                      |
| -------------- | ----------------------------------------------- |
| IaC            | Terraform 1.14.8, AzureRM provider ~> 4.60.0    |
| Configuration  | Ansible (Local-Pull via cloud-init)             |
| CI/CD          | Azure DevOps Pipelines                          |
| Cloud          | Microsoft Azure (westeurope)                    |
| Authentication | OIDC Federated Identity Credential              |
| Web Server     | Nginx (reverse-proxy + API server)              |
| Compute        | VMSS Ubuntu 22.04 LTS (Standard_B2s)            |
| Load Testing   | Azure Load Testing + JMeter                     |
| Observability  | Log Analytics, Azure Monitor, Network Watcher   |
| Governance     | Azure Policy, Consumption Budget, Action Groups |

---

## License

See [LICENSE](LICENSE) for details.
