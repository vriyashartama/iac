output "harbor_admin_password" {
  value = random_string.harbor_admin_password.id
}

output "harbor_secret_key" {
  value = random_string.harbor_secret_key.id
}

output "minio_access_key" {
  value = random_string.minio_access_key.id
}

output "minio_secret_key" {
  value = random_uuid.minio_secret_key.id
}