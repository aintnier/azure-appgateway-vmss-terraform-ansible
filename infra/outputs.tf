# ============================================================================
# Outputs
# ============================================================================

output "resource_group_name" {
  description = "Name of the Resource Group"
  value       = azurerm_resource_group.this.name
}

output "appgw_public_ip" {
  description = "Public IP address of the Application Gateway (use for curl tests)"
  value       = azurerm_public_ip.appgw.ip_address
}

output "internal_lb_private_ip" {
  description = "Private IP of the Internal Standard Load Balancer"
  value       = azurerm_lb.internal.private_ip_address
}

output "bastion_dns_name" {
  description = "DNS name of the Azure Bastion host"
  value       = azurerm_bastion_host.this.dns_name
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.this.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.this.vault_uri
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.this.id
}

output "frontend_vmss_id" {
  description = "Resource ID of the Frontend VMSS"
  value       = azurerm_linux_virtual_machine_scale_set.frontend.id
}

output "backend_vmss_id" {
  description = "Resource ID of the Backend VMSS"
  value       = azurerm_linux_virtual_machine_scale_set.backend.id
}

output "load_test_id" {
  description = "Resource ID of the Azure Load Testing instance"
  value       = azurerm_load_test.this.id
}
