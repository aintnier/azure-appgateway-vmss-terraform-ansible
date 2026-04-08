# ============================================================================
# Governance - Budget, Azure Policy, Action Groups, Log Analytics, Alerts
# ============================================================================

# ---
# Action Group (Email notifications for budget + autoscale alerts)
# ---

resource "azurerm_monitor_action_group" "this" {
  name                = "ag-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = "agaction"

  email_receiver {
    name          = "alert-email"
    email_address = var.alert_email
  }

  tags = local.common_tags
}

# ---
# Consumption Budget (Resource Group level)
# ---

resource "azurerm_consumption_budget_resource_group" "this" {
  name              = "budget-${local.name_suffix}"
  resource_group_id = azurerm_resource_group.this.id
  amount            = var.budget_amount
  time_grain        = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  notification {
    operator       = "GreaterThanOrEqualTo"
    threshold      = var.budget_threshold_warning
    contact_groups = [azurerm_monitor_action_group.this.id]
    threshold_type = "Actual"
  }

  notification {
    operator       = "GreaterThanOrEqualTo"
    threshold      = var.budget_threshold_critical
    contact_groups = [azurerm_monitor_action_group.this.id]
    threshold_type = "Actual"
  }
}

# ---
# Azure Policy - Allowed VM SKUs
# Built-in policy: "Allowed virtual machine size SKUs"
# ---

resource "azurerm_resource_group_policy_assignment" "allowed_vm_skus" {
  name                 = "policy-allowed-vm-skus"
  resource_group_id    = azurerm_resource_group.this.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/cccc23c7-8427-4f53-ad12-b6a63eb452b3"
  display_name         = "Allowed VM SKUs"
  description          = "Restrict VM sizes to cost-governed SKUs: Standard_B1s, Standard_B2s, Standard_D2s_v3"
  enforce              = true

  parameters = jsonencode({
    listOfAllowedSKUs = {
      value = ["Standard_B1s", "Standard_B2s", "Standard_D2s_v3"]
    }
  })
}

# ---
# Azure Policy - Allowed Locations (westeurope only)
# Built-in policy: "Allowed locations"
# ---

resource "azurerm_resource_group_policy_assignment" "allowed_locations" {
  name                 = "policy-allowed-locations"
  resource_group_id    = azurerm_resource_group.this.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
  display_name         = "Allowed Locations"
  description          = "Restrict resource deployment to westeurope only"
  enforce              = true

  parameters = jsonencode({
    listOfAllowedLocations = {
      value = ["westeurope"]
    }
  })
}

# ---
# Log Analytics Workspace
# ---

resource "azurerm_log_analytics_workspace" "this" {
  name                = "law-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

# ---
# Diagnostic Settings - Application Gateway -> Log Analytics
# ---

resource "azurerm_monitor_diagnostic_setting" "appgw" {
  name                       = "diag-appgw"
  target_resource_id         = azurerm_application_gateway.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }

  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# ---
# Activity Log Alert - Autoscale Scale-Up Events
# ---

resource "azurerm_monitor_activity_log_alert" "autoscale" {
  name                = "alert-autoscale-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = "Global"
  scopes              = [azurerm_resource_group.this.id]
  description         = "Alert when VMSS Frontend autoscale triggers a scale-out event"

  criteria {
    operation_name = "Microsoft.Insights/AutoscaleSettings/Scaleup/Action"
    category       = "Autoscale"
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }

  tags = local.common_tags
}
