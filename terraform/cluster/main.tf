# Variables - Add these at the top of your file
variable "client_id" {
  description = "Azure Client ID"
  type        = string
  default     = ""
}

variable "client_secret" {
  description = "Azure Client Secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tenant_id" {
  description = "Azure Tenant ID"
  type        = string
  default     = ""
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
  default     = ""
}

# Provider configuration - FIXED
provider "azurerm" {
  features {}

  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
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

# Add outputs for Jenkins pipeline
output "acr_url" {
  description = "The URL of the Azure Container Registry"
  value       = azurerm_container_registry.acr.login_server
}

output "aks_api_server" {
  description = "The API server endpoint for the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.kube_config.0.host
}
