variable "ghClientId" {
  type = string
  description = "Github Client ID"
}

variable "ghClientSecret" {
  type = string
  description = "Github Client Secret"
}

variable "droneGhOrg" {
  type = string
  description = "Drone GitHub Organization Name"
}

variable "droneGhAdmin" {
  type = string
  description = "Drone GitHub Admin"
}

variable "acmeEmailAddress" {
  type = string
  description = "Acme Email Address"
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