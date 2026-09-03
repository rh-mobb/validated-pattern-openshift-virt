data "azurerm_client_config" "current" {}

locals {
  tags        = merge(var.tags, { project = "openshift-virt-anf" })
  subnet_name = coalesce(var.subnet_name, "${var.cluster_name}-netapp")
  rg_id       = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
}

# ANF delegated subnet must be empty of NICs and must not have an NSG.
resource "azurerm_subnet" "netapp" {
  name                 = local.subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.vnet_name
  address_prefixes     = [var.subnet_prefix]

  delegation {
    name = "netapp-volumes"
    service_delegation {
      name = "Microsoft.Netapp/volumes"
      actions = [
        "Microsoft.Network/networkinterfaces/*",
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_netapp_account" "this" {
  name                = "${var.cluster_name}-anf"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_netapp_pool" "this" {
  name                    = "${var.cluster_name}-anf-pool"
  account_name            = azurerm_netapp_account.this.name
  location                = var.location
  resource_group_name     = var.resource_group_name
  service_level           = var.service_level
  size_in_tb              = var.pool_size_tib
  qos_type                = "Manual"
  custom_throughput_mibps = var.custom_throughput_mibps
  tags                    = local.tags
}
