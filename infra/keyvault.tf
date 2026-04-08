# ============================================================================
# Key Vault - TLS Certificate, SSH Key, Managed Identity for AppGW
# ============================================================================

data "azurerm_client_config" "current" {}

# ---
# Random suffix for Key Vault (globally unique name, max 24 chars)
# ---

resource "random_string" "kv_suffix" {
  length  = 6
  special = false
  upper   = false
}

# ---
# Key Vault (RBAC authorization)
# ---

resource "azurerm_key_vault" "this" {
  name                       = "kv-${var.environment}-${random_string.kv_suffix.result}"
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
  tags                       = local.common_tags
}

# ---
# RBAC - Current identity as Key Vault Administrator
# ---

resource "azurerm_role_assignment" "current_kv_admin" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---
# Managed Identity for Application Gateway -> Key Vault access
# ---

resource "azurerm_user_assigned_identity" "appgw" {
  name                = "id-appgw-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags
}

resource "azurerm_role_assignment" "appgw_kv_secrets" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.appgw.principal_id
}

# ---
# SSH Key (RSA 4096)
# ---

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_key_vault_secret" "ssh_private_key" {
  name         = "vmss-ssh-private-key"
  value        = tls_private_key.ssh.private_key_pem
  key_vault_id = azurerm_key_vault.this.id
  tags         = local.common_tags

  depends_on = [azurerm_role_assignment.current_kv_admin]
}

# ---
# Self-Signed TLS Certificate for Application Gateway
# ---

resource "azurerm_key_vault_certificate" "appgw" {
  name         = "appgw-ssl-cert"
  key_vault_id = azurerm_key_vault.this.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      subject            = "CN=appgw.lab.local"
      validity_in_months = 1

      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]
    }
  }

  tags = local.common_tags

  depends_on = [azurerm_role_assignment.current_kv_admin]
}
