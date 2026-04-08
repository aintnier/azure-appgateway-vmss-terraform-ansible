# ---
# Remote State Backend (Azure Storage Account)
# The Storage Account, Container, and Resource Group below must be
# provisioned BEFORE running `terraform init`. See README.md for
# the bootstrap Azure CLI commands.
# ---

terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstate080426"
    container_name       = "tfstate"
    key                  = "appgateway-vmss.tfstate"
    use_oidc             = true
  }
}
