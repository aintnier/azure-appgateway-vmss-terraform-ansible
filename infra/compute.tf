# ============================================================================
# Compute - Frontend VMSS, Backend VMSS, Autoscale Setting
# ============================================================================

# ---
# Frontend VMSS (Web Tier - Nginx Reverse Proxy)
# Associated with Application Gateway backend pool.
# ---

resource "azurerm_linux_virtual_machine_scale_set" "frontend" {
  name                = "vmss-frontend-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = var.vmss_frontend_sku
  instances           = var.vmss_frontend_default
  admin_username      = var.admin_username
  overprovision       = false
  upgrade_mode        = "Automatic"
  custom_data = base64encode(
    templatefile("${path.module}/scripts/cloud-init.sh.tpl", {
      server_role   = "frontend"
      backend_lb_ip = azurerm_lb.internal.private_ip_address
    })
  )

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  network_interface {
    name    = "nic-frontend"
    primary = true

    ip_configuration {
      name      = "ipconfig-frontend"
      primary   = true
      subnet_id = azurerm_subnet.subnets["frontend"].id

      application_gateway_backend_address_pool_ids = [
        local.appgw_frontend_pool_id,
      ]
    }
  }

  tags = local.common_tags

  depends_on = [
    azurerm_application_gateway.this,
    azurerm_subnet_network_security_group_association.frontend,
  ]
}

# ---
# Autoscale Setting - Frontend VMSS
# CPU > 70% -> scale-out +1 (within 5 min)
# CPU < 30% -> scale-in  -1
# ---

resource "azurerm_monitor_autoscale_setting" "frontend" {
  name                = "autoscale-frontend-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.frontend.id

  profile {
    name = "default-profile"

    capacity {
      default = var.vmss_frontend_default
      minimum = var.vmss_frontend_min
      maximum = var.vmss_frontend_max
    }

    # --- Scale-Out Rule ---
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.frontend.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # --- Scale-In Rule ---
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.frontend.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  notification {
    email {
      custom_emails = [var.alert_email]
    }
  }

  tags = local.common_tags
}

# ---
# Backend VMSS (API Tier - Nginx API Server)
# Associated with Internal Standard Load Balancer.
# ---

resource "azurerm_linux_virtual_machine_scale_set" "backend" {
  name                = "vmss-backend-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = var.vmss_backend_sku
  instances           = var.vmss_backend_instances
  admin_username      = var.admin_username
  overprovision       = false
  upgrade_mode        = "Automatic"

  custom_data = base64encode(
    templatefile("${path.module}/scripts/cloud-init.sh.tpl", {
      server_role   = "backend"
      backend_lb_ip = azurerm_lb.internal.private_ip_address
    })
  )

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  network_interface {
    name    = "nic-backend"
    primary = true

    ip_configuration {
      name      = "ipconfig-backend"
      primary   = true
      subnet_id = azurerm_subnet.subnets["backend"].id

      load_balancer_backend_address_pool_ids = [
        azurerm_lb_backend_address_pool.backend.id,
      ]
    }
  }

  tags = local.common_tags

  depends_on = [
    azurerm_lb_rule.http,
    azurerm_subnet_network_security_group_association.backend,
  ]
}
