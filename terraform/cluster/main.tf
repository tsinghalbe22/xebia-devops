provider "azurerm" {
  features {}

  client_id       = var.client_id != "" ? var.client_id : (terraform.env("CLIENT_ID") != "" ? terraform.env("CLIENT_ID") : "")
  client_secret   = var.client_secret != "" ? var.client_secret : (terraform.env("CLIENT_SECRET") != "" ? terraform.env("CLIENT_SECRET") : "")
  tenant_id       = var.tenant_id != "" ? var.tenant_id : (terraform.env("TENANT_ID") != "" ? terraform.env("TENANT_ID") : "")
  subscription_id = var.subscription_id != "" ? var.subscription_id : (terraform.env("SUBSCRIPTION_ID") != "" ? terraform.env("SUBSCRIPTION_ID") : "")
}

resource "azurerm_resource_group" "rg" {
  name     = "docker-vm-rg"
  location = "Central India"
}

# Azure Container Registry (ACR)
resource "azurerm_container_registry" "acr" {
  name                     = "dockeracrxyz"  # This should be globally unique
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  sku                      = "Basic"
  admin_enabled            = true
}

# Azure Kubernetes Service (AKS)
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "docker-aks-cluster"
  location           = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "dockeraks"
  kubernetes_version  = "1.30.12"  # Choose a stable version
  
  default_node_pool {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_B2s"
  }

  identity {
    type = "SystemAssigned"
  }
}

# Azure Virtual Network (VNet)
resource "azurerm_virtual_network" "vnet" {
  name                = "docker-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Azure Subnet for AKS
resource "azurerm_subnet" "subnet" {
  name                 = "docker-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Output the required information
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
