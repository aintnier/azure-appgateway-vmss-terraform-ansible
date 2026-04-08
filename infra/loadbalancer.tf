# ============================================================================
# Standard Load Balancer - Internal L4, Frontend IP in Backend Subnet
# ============================================================================

resource "azurerm_lb" "internal" {
  name                = "lb-internal-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "frontend-ip-internal"
    subnet_id                     = azurerm_subnet.subnets["backend"].id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(var.subnet_cidrs["backend"], 10)
  }

  tags = local.common_tags
}

# ---
# Backend Address Pool
# ---

resource "azurerm_lb_backend_address_pool" "backend" {
  name            = "backend-pool"
  loadbalancer_id = azurerm_lb.internal.id
}

# ---
# Health Probe (TCP 80)
# ---

resource "azurerm_lb_probe" "backend" {
  name                = "probe-http"
  loadbalancer_id     = azurerm_lb.internal.id
  protocol            = "Http"
  port                = 80
  request_path        = "/health"
  interval_in_seconds = 15
  number_of_probes    = 2
}

# ---
# Load Balancing Rule (TCP 80 -> 80)
# ---

resource "azurerm_lb_rule" "http" {
  name                           = "rule-http"
  loadbalancer_id                = azurerm_lb.internal.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "frontend-ip-internal"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.backend.id]
  probe_id                       = azurerm_lb_probe.backend.id
  floating_ip_enabled            = false
  idle_timeout_in_minutes        = 4
  load_distribution              = "Default"
}
