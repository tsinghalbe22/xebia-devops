terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}

  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
}

#— DATA SOURCES (existing infra) —#
data "azurerm_resource_group" "existing" {
  name = "docker-vm-rg"
}

data "azurerm_virtual_network" "existing" {
  name                = "docker-vnet"
  resource_group_name = data.azurerm_resource_group.existing.name
}

data "azurerm_subnet" "existing" {
  name                 = "docker-subnet"
  resource_group_name  = data.azurerm_resource_group.existing.name
  virtual_network_name = data.azurerm_virtual_network.existing.name
}

data "azurerm_network_security_group" "existing" {
  name                = "docker-nsg"
  resource_group_name = data.azurerm_resource_group.existing.name
}

#— NEW PUBLIC IP & NIC for docker-vm-2 —#
resource "azurerm_public_ip" "vm2_pip" {
  name                = "docker-vm-2-pip"
  location            = data.azurerm_resource_group.existing.location
  resource_group_name = data.azurerm_resource_group.existing.name

  allocation_method = "Static"
  sku               = "Standard"
}

resource "azurerm_network_interface" "vm2_nic" {
  name                = "docker-vm-2-nic"
  location            = data.azurerm_resource_group.existing.location
  resource_group_name = data.azurerm_resource_group.existing.name

  ip_configuration {
    name                          = "ipconfig2"
    subnet_id                     = data.azurerm_subnet.existing.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm2_pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "vm2_nic_nsg" {
  network_interface_id      = azurerm_network_interface.vm2_nic.id
  network_security_group_id = data.azurerm_network_security_group.existing.id
}

#— THE SECOND LINUX VM —#
resource "azurerm_linux_virtual_machine" "vm2" {
  name                  = "docker-vm-2"
  location              = data.azurerm_resource_group.existing.location
  resource_group_name   = data.azurerm_resource_group.existing.name
  size                  = "Standard_B2als_v2"
  admin_username        = "azureuser"
  network_interface_ids = [azurerm_network_interface.vm2_nic.id]

  # password auth only
  disable_password_authentication = false
  admin_password                  = "Test1!"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

#— OUTPUT —#
output "public_ip_vm_2" {
  description = "Static public IP of docker-vm-2"
  value       = azurerm_public_ip.vm2_pip.ip_address
}
