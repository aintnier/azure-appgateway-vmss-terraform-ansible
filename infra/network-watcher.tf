# ============================================================================
# Network Watcher - Use existing (one per region per subscription limit)
# ============================================================================

data "azurerm_network_watcher" "this" {
  name                = "NetworkWatcher_${var.location}"
  resource_group_name = "NetworkWatcherRG"
}
