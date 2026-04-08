# ============================================================================
# Application Gateway - WAF v2, Basic Rule -> Frontend Pool Only
# ============================================================================

resource "azurerm_application_gateway" "this" {
  name                = "appgw-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = 1
    max_capacity = 2
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.appgw.id]
  }

  # --- Gateway IP Configuration ---
  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.subnets["appgw"].id
  }

  # --- Frontend IP (Public) ---
  frontend_ip_configuration {
    name                 = "frontend-ip-public"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  # --- Frontend Port (HTTPS 443) ---
  frontend_port {
    name = "https-port"
    port = 443
  }

  # --- SSL Certificate from Key Vault ---
  ssl_certificate {
    name                = "appgw-ssl-cert"
    key_vault_secret_id = azurerm_key_vault_certificate.appgw.versionless_secret_id
  }

  # --- Single Backend Pool: Frontend VMSS ---
  backend_address_pool {
    name = "frontend-pool"
  }

  # --- Backend HTTP Settings ---
  backend_http_settings {
    name                  = "http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
    probe_name            = "health-probe"
  }

  # --- Health Probe ---
  probe {
    name                = "health-probe"
    protocol            = "Http"
    path                = "/health"
    host                = "127.0.0.1"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
    pick_host_name_from_backend_http_settings = true
  }

  # --- HTTPS Listener ---
  http_listener {
    name                           = "https-listener"
    frontend_ip_configuration_name = "frontend-ip-public"
    frontend_port_name             = "https-port"
    protocol                       = "Https"
    ssl_certificate_name           = "appgw-ssl-cert"
  }

  # --- Basic Routing Rule (ALL traffic -> Frontend Pool) ---
  request_routing_rule {
    name                       = "basic-rule"
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = "https-listener"
    backend_address_pool_name  = "frontend-pool"
    backend_http_settings_name = "http-settings"
  }

  # --- WAF Configuration: Detection Mode, OWASP 3.2 ---
  waf_configuration {
    enabled          = true
    firewall_mode    = "Detection"
    rule_set_type    = "OWASP"
    rule_set_version = "3.2"
  }

  tags = local.common_tags

  depends_on = [
    azurerm_role_assignment.appgw_kv_secrets,
    azurerm_subnet_network_security_group_association.appgw,
  ]
}
