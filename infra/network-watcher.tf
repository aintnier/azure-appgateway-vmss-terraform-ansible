# ============================================================================
# Network Watcher - Portal-only diagnostics (IP Flow Verify, Topology)
# ============================================================================

resource "azurerm_network_watcher" "this" {
  name                = "nw-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags
}
