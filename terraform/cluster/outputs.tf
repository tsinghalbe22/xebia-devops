output "acr_url" {
  value = azurerm_container_registry.acr.login_server
}

output "aks_api_server" {
  value     = azurerm_kubernetes_cluster.aks.kube_config.0.host
  sensitive = true
}

output "aks_client_id" {
  value     = azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate
  sensitive = true
}
