resource "azurerm_user_assigned_identity" "bgp" {
  name                = "${var.cluster_name}-bgp"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_role_definition" "bgp_cloud_connector" {
  name        = "${var.cluster_name}-bgp-cloud-connector"
  scope       = local.rg_id
  description = "bgp-cloud-connector: Azure Route Server BGP connections in the customer RG."

  permissions {
    actions = [
      "Microsoft.Network/virtualHubs/read",
      "Microsoft.Network/virtualHubs/ipConfigurations/read",
      "Microsoft.Network/virtualHubs/bgpConnections/read",
      "Microsoft.Network/virtualHubs/bgpConnections/write",
      "Microsoft.Network/virtualHubs/bgpConnections/delete",
      "Microsoft.Network/virtualNetworks/read",
      "Microsoft.Network/virtualNetworks/subnets/read",
    ]
    not_actions = []
  }

  assignable_scopes = [local.rg_id]
}

resource "azurerm_role_assignment" "bgp_cloud_connector" {
  scope                            = local.rg_id
  role_definition_id               = azurerm_role_definition.bgp_cloud_connector.role_definition_resource_id
  principal_id                     = azurerm_user_assigned_identity.bgp.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_federated_identity_credential" "bgp" {
  count = trimspace(var.oidc_issuer_url) != "" ? 1 : 0

  name      = "bgp-cloud-connector"
  parent_id = azurerm_user_assigned_identity.bgp.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = var.oidc_issuer_url
  subject   = var.bgp_federated_subject
}
