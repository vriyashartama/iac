provider "azurerm" {
  features {}
}

resource "random_pet" "prefix" {}

resource "random_uuid" "azure_file_share_key" {}

# Create resource group
resource "azurerm_resource_group" "default" {
  name     = "${random_pet.prefix.id}-rg"
  location = var.azRegion
}

# Create virtual network
resource "azurerm_virtual_network" "default" {
  name                = "${random_pet.prefix.id}-vnet"
  location            = var.azRegion
  address_space       = ["10.0.0.0/16"]
  resource_group_name = azurerm_resource_group.default.name
}

# Create subnet
resource "azurerm_subnet" "default" {
  name = "${random_pet.prefix.id}-subnet"
  address_prefixes      = ["10.0.1.0/24"]
  virtual_network_name = azurerm_virtual_network.default.name
  resource_group_name  = azurerm_resource_group.default.name
}

# Create public IP
resource "azurerm_public_ip" "default" {
  name                = "${random_pet.prefix.id}-ip"
  allocation_method   = "Static"
  location            = var.azRegion
  resource_group_name = azurerm_resource_group.default.name
}

# Create network security group and rule
resource "azurerm_network_security_group" "default" {
  name                = "${random_pet.prefix.id}-secgroup"
  location            = var.azRegion
  resource_group_name = azurerm_resource_group.default.name
}

resource "azurerm_network_security_rule" "i01" {
  name                       = "SSH"
  priority                   = 1002
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "22"
  source_address_prefix      = "*"
  destination_address_prefix = "*"
  resource_group_name         = azurerm_resource_group.default.name
  network_security_group_name = azurerm_network_security_group.default.name
}

resource "azurerm_network_security_rule" "i02" {
  name                       = "Allow Kubernetes API"
  priority                   = 1003
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "*"
  source_port_range          = "*"
  destination_port_range     = "*"
  source_address_prefix      = "${var.localIpAddress}"
  destination_address_prefix = "*"
  resource_group_name         = azurerm_resource_group.default.name
  network_security_group_name = azurerm_network_security_group.default.name
}

resource "azurerm_network_security_rule" "i03" {
  name                       = "Allow HTTP HTTPS Traffic"
  priority                   = 1001
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_ranges    = ["80", "433"]
  source_address_prefix      = "*"
  destination_address_prefix = "*"
  resource_group_name         = azurerm_resource_group.default.name
  network_security_group_name = azurerm_network_security_group.default.name
}

resource "azurerm_network_interface" "default" {
  name                = "${random_pet.prefix.id}-nic"
  location            = var.azRegion
  resource_group_name = azurerm_resource_group.default.name

  ip_configuration {
    name                          = "${random_pet.prefix.id}-ipconf"
    public_ip_address_id          = azurerm_public_ip.default.id
    subnet_id                     = azurerm_subnet.default.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Connect security group to network interface
resource "azurerm_network_interface_security_group_association" "default" {
  network_interface_id      = azurerm_network_interface.default.id
  network_security_group_id = azurerm_network_security_group.default.id
}

output "public_ip" {
  value = azurerm_public_ip.default.ip_address
}

output "azure_file_share_key" {
  value = random_uuid.azure_file_share_key.id
}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "default" {
  name                  = "${random_pet.prefix.id}-vm"
  location              = var.azRegion
  resource_group_name   = azurerm_resource_group.default.name
  network_interface_ids = [azurerm_network_interface.default.id]
  size                  = var.azVmSize

  os_disk {
    name                 = "${random_pet.prefix.id}-disk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  computer_name  = "${random_pet.prefix.id}-vm"
  disable_password_authentication = true
  admin_username = var.azVmUsername

  admin_ssh_key {
    username    = var.azVmUsername
    public_key  = file(var.azVmSshPath)
  }

  provisioner "local-exec" {
    command = <<EOT
      sleep 30 && \
      k3sup install \
      --k3s-extra-args '--no-deploy traefik' \t
      --ip ${azurerm_public_ip.default.ip_address} \
      --ssh-key ~/.ssh/id_rsa \
      --user azureuser \
    EOT 
  }
}

resource "random_string" "azure_storage_name" {
  length = 16
  special = false
  upper = false
}


output "azure_storage_name" {
  value = random_string.azure_storage_name.id
}

resource "azurerm_storage_account" "default" {
  name                      = "${random_string.azure_storage_name.id}0sa"
  location                  = var.azRegion
  resource_group_name       = azurerm_resource_group.default.name
  account_tier              = "Standard"
  account_replication_type  = "LRS"
}
resource "azurerm_storage_share" "default" {
  name                  = random_string.azure_storage_name.id
  storage_account_name  = azurerm_storage_account.default.name
  quota                 = 10

  acl {
    id = random_uuid.azure_file_share_key.id

    access_policy {
      permissions = "rwdl"
    }
  }
}

provider "cloudflare" {
  email   = var.cfEmail
  api_key = var.cfApiKey
}

resource "cloudflare_record" "domain" {
  zone_id = var.cfZoneId
  name    = "pipeline.dev"
  value   = azurerm_public_ip.default.ip_address
  type    = "A"
  proxied = false
}

output "public_domain" {
  value = cloudflare_record.domain.hostname
}

resource "cloudflare_record" "subdomain" {
  zone_id = var.cfZoneId
  name    = "*.pipeline.dev"
  value   = azurerm_public_ip.default.ip_address
  type    = "A"
  proxied = false
}