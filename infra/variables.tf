# ============================================================================
# Variables - Azure AppGateway & VMSS Terraform Lab
# ============================================================================

# ---
# Project & Tagging
# ---

variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "azure-appgateway-vmss-terraform-ansible"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "owner" {
  description = "Owner tag value"
  type        = string
  default     = "Ernesto"
}

variable "ttl" {
  description = "Time-to-live tag for the lab session"
  type        = string
  default     = "4h"
}

variable "cost_center" {
  description = "Cost center tag for FinOps tracking"
  type        = string
  default     = "INFRA"
}

# ---
# Region
# ---

variable "location" {
  description = "Azure region - locked to westeurope by Azure Policy"
  type        = string
  default     = "westeurope"
}

# ---
# Networking
# ---

variable "vnet_address_space" {
  description = "Address space for the main Virtual Network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidrs" {
  description = "CIDR blocks for each subnet keyed by logical name"
  type        = map(string)
  default = {
    appgw    = "10.0.1.0/24"
    frontend = "10.0.2.0/24"
    backend  = "10.0.3.0/24"
    bastion  = "10.0.4.0/26"
  }
}

# ---
# Compute - VMSS
# ---

variable "vmss_frontend_sku" {
  description = "VM SKU for the Frontend VMSS"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "vmss_backend_sku" {
  description = "VM SKU for the Backend VMSS"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "vmss_frontend_min" {
  description = "Minimum instance count for Frontend VMSS autoscale"
  type        = number
  default     = 2
}

variable "vmss_frontend_max" {
  description = "Maximum instance count for Frontend VMSS autoscale"
  type        = number
  default     = 5
}

variable "vmss_frontend_default" {
  description = "Default (baseline) instance count for Frontend VMSS"
  type        = number
  default     = 2
}

variable "vmss_backend_instances" {
  description = "Fixed instance count for Backend VMSS"
  type        = number
  default     = 2
}

variable "admin_username" {
  description = "Admin username for VMSS instances"
  type        = string
  default     = "azureadmin"
}

# ---
# Governance & Monitoring
# ---

variable "budget_amount" {
  description = "Monthly budget amount in EUR for the Resource Group"
  type        = number
  default     = 6
}

variable "budget_threshold_warning" {
  description = "Budget notification threshold percentage for warning"
  type        = number
  default     = 50
}

variable "budget_threshold_critical" {
  description = "Budget notification threshold percentage for critical"
  type        = number
  default     = 80
}

variable "alert_email" {
  description = "Email address for cost and autoscale alert notifications"
  type        = string
  default     = "aintnier+azure-appgateway-vmss-terraform-ansible@gmail.com"
}

variable "budget_start_date" {
  description = "Start date for the consumption budget (first day of a month, RFC3339)"
  type        = string
  default     = "2026-04-01T00:00:00Z"
}

# ============================================================================
# Locals
# ============================================================================

locals {
  # --- Naming ---
  name_suffix = "${var.project}-${var.environment}"

  # --- Standard Tags (mandatory on every resource) ---
  common_tags = {
    project     = var.project
    managed_by  = "terraform"
    environment = var.environment
    owner       = var.owner
    ttl         = var.ttl
    cost-center = var.cost_center
  }

  # --- Dependency Chain Locals (try() for safe destruction order) ---
  resource_group_id   = try(azurerm_resource_group.this.id, "")
  resource_group_name = try(azurerm_resource_group.this.name, "")
  vnet_id             = try(azurerm_virtual_network.this.id, "")

  # --- AppGW Backend Pool ID (single pool - Basic rule) ---
  appgw_frontend_pool_id = try(
    one([
      for pool in azurerm_application_gateway.this.backend_address_pool : pool.id
      if pool.name == "frontend-pool"
    ]),
    ""
  )

  # --- Internal LB IP (static in backend-subnet) ---
  internal_lb_ip = try(azurerm_lb.internal.private_ip_address, "10.0.3.10")
}
