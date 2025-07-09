output "acr_url" {
  value       = azurerm_container_registry.acr.login_server
  description = "The URL of the Azure Container Registry"
}

output "acr_name" {
  value       = azurerm_container_registry.acr.name
  description = "The name of the Azure Container Registry"
}

output "aks_api_server" {
  value       = azurerm_kubernetes_cluster.aks.kube_config.0.host
  description = "The API server URL of the AKS cluster"
  sensitive   = true
}

output "aks_cluster_name" {
  value       = azurerm_kubernetes_cluster.aks.name
  description = "The name of the AKS cluster"
}

output "resource_group_name" {
  value       = azurerm_resource_group.rg.name
  description = "The name of the resource group"
}
