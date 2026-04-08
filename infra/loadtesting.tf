# ============================================================================
# Azure Load Testing - IaC-provisioned load test resource
# ============================================================================

resource "azurerm_load_test" "this" {
  name                = "lt-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags
}
