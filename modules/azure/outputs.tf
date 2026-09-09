output "subnet_id" {
  value = azurerm_subnet.netapp.id
}

output "subnet_name" {
  value = azurerm_subnet.netapp.name
}

output "subnet_prefix" {
  value = var.subnet_prefix
}

output "netapp_account_name" {
  value = azurerm_netapp_account.this.name
}

output "netapp_account_id" {
  value = azurerm_netapp_account.this.id
}

output "capacity_pool_name" {
  value = azurerm_netapp_pool.this.name
}

output "trident_identity_id" {
  value = azurerm_user_assigned_identity.trident.id
}

output "trident_client_id" {
  value = azurerm_user_assigned_identity.trident.client_id
}

output "trident_principal_id" {
  value = azurerm_user_assigned_identity.trident.principal_id
}

output "route_server_name" {
  value = azurerm_route_server.this.name
}

output "route_server_id" {
  value = azurerm_route_server.this.id
}

output "route_server_subnet_prefix" {
  value = var.route_server_subnet_prefix
}

output "bgp_client_id" {
  value = azurerm_user_assigned_identity.bgp.client_id
}

output "bgp_identity_id" {
  value = azurerm_user_assigned_identity.bgp.id
}

output "network_interface_client_id" {
  value = var.network_interface_client_id
}
