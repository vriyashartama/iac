output "public_domain" {
  value = cloudflare_record.domain.hostname
}

output "public_ip" {
  value = azurerm_public_ip.default.ip_address
}

output "azure_file_share_key" {
  value = random_uuid.azure_file_share_key.id
}