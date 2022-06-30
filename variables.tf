variable "azRegion" {
  type = string
  default = "Southeast Asia"
  description = "Azure region selection"
}

variable "azVmSize" {
  type = string
  default = "Standard_D4s_v3"
  description = "Azure VM size"
}

variable "azVmUsername" {
  type = string
  default = "azureuser"
  description = "Azure VM username"
}

variable "azVmSshPath" {
  type = string
  default = "~/.ssh/id_rsa.pub"
  description = "Azure VM SSH key location"
}

variable "localIpAddress" {
  type = string
  description = "Local IP address for accessing the virtual machine"
  default = "*"
}

variable "cfEmail" {
  type = string
  description = "Clouflare API email address"
}

variable "cfApiKey" {
  type = string
  description = "Clouflare API key"
}

variable "cfZoneId" {
  type = string
  description = "Clouflare Zone ID"
}