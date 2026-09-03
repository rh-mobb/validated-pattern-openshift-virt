resource "azurerm_user_assigned_identity" "trident" {
  name                = "${var.cluster_name}-trident"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_role_definition" "trident_anf" {
  name        = "${var.cluster_name}-trident-anf"
  scope       = local.rg_id
  description = "Trident CSI: manage ANF volumes in this resource group."

  permissions {
    actions = [
      "Microsoft.NetApp/netAppAccounts/read",
      "Microsoft.NetApp/netAppAccounts/capacityPools/read",
      "Microsoft.NetApp/netAppAccounts/capacityPools/volumes/*",
      "Microsoft.NetApp/netAppAccounts/capacityPools/volumes/snapshots/*",
      "Microsoft.Network/virtualNetworks/read",
      "Microsoft.Network/virtualNetworks/subnets/read",
      "Microsoft.Features/features/read",
    ]
    not_actions = []
  }

  assignable_scopes = [local.rg_id]
}

resource "azurerm_role_assignment" "trident_anf" {
  scope                            = local.rg_id
  role_definition_id               = azurerm_role_definition.trident_anf.role_definition_resource_id
  principal_id                     = azurerm_user_assigned_identity.trident.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_federated_identity_credential" "trident" {
  count = trimspace(var.oidc_issuer_url) != "" ? 1 : 0

  name      = "trident-controller"
  parent_id = azurerm_user_assigned_identity.trident.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = var.oidc_issuer_url
  subject   = var.trident_federated_subject
}
