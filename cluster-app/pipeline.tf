locals {
  settings = yamldecode(file("../kubeconfig"))
}

# Load host terraform state from upper directory
data "terraform_remote_state" "k3s" {
  backend = "local"

  config = {
    path = "../terraform.tfstate"
  }
}

provider "kubectl" {
  host = local.settings.clusters[0].cluster.server

  client_certificate      = base64decode(local.settings.users[0].user.client-certificate-data)
  client_key             = base64decode(local.settings.users[0].user.client-key-data)
  cluster_ca_certificate  = base64decode(local.settings.clusters[0].cluster.certificate-authority-data)
  load_config_file         = false
}

provider "helm" {
  kubernetes {
    config_path = "../kubeconfig"
  }
}

resource "random_string" "drone_rpc_secret" {
  length = 32
  special = false
}

resource "random_string" "minio_access_key" {
  length = 32
  special = false
}

resource "random_string" "harbor_admin_password" {
  length = 16
  special = false
}


resource "random_string" "harbor_secret_key" {
  length = 16
  special = false
}

resource "random_uuid" "minio_secret_key" {
}

data "kubectl_path_documents" "default" {
  pattern = "${path.module}/manifest/global/*.yaml"
  vars = {
      azurestorageaccountname = base64encode(data.terraform_remote_state.k3s.outputs.azure_storage_name)
      azurestorageaccountkey = base64encode(data.terraform_remote_state.k3s.outputs.azure_file_share_key)
      azure_share_name = data.terraform_remote_state.k3s.outputs.azure_storage_name
      root_host = data.terraform_remote_state.k3s.outputs.public_domain
    }
}

data "kubectl_path_documents" "ingress" {
  pattern = "${path.module}/manifest/ingress/*.yaml"
  vars = {
      root_host = data.terraform_remote_state.k3s.outputs.public_domain
    }
}

data "kubectl_path_documents" "argocd" {
  pattern = "${path.module}/manifest/argocd/*.yaml"
  vars = {
      root_host = data.terraform_remote_state.k3s.outputs.public_domain
    }
}

data "kubectl_path_documents" "traefik" {
  pattern = "${path.module}/manifest/traefik/*.yaml"
  vars = {
      azurestorageaccountname = base64encode(data.terraform_remote_state.k3s.outputs.azure_storage_name)
      azurestorageaccountkey = base64encode(data.terraform_remote_state.k3s.outputs.azure_file_share_key)
      azure_share_name = data.terraform_remote_state.k3s.outputs.azure_storage_name
      acme_email_address = var.acmeEmailAddress
      cf_api_email = var.cfEmail
      cf_api_key = var.cfApiKey
      cf_zone_api_token = var.cfZoneId
      root_host = data.terraform_remote_state.k3s.outputs.public_domain
    }
}

data "kubectl_path_documents" "drone" {
    pattern = "${path.module}/manifest/drone/*.yaml"
    vars = {
        root_host = data.terraform_remote_state.k3s.outputs.public_domain
        github_client_id = var.ghClientId
        github_client_secret = var.ghClientSecret
        drone_rpc_secret = random_string.drone_rpc_secret.id
        drone_server_proto = "https"
        drone_user_create = "username:${var.droneGhAdmin},admin:true"
        drone_user_filter = var.droneGhOrg  
    }
}

data "kubectl_path_documents" "drone_runner" {
    pattern = "${path.module}/manifest/drone-runner/*.yaml"
    vars = {
        host = "ci.${data.terraform_remote_state.k3s.outputs.public_domain}"
        drone_rpc_secret = random_string.drone_rpc_secret.id
        drone_rpc_proto = "https"
    }


}

resource "kubectl_manifest" "default" {
  count     = length(data.kubectl_path_documents.default.documents)
  yaml_body = element(data.kubectl_path_documents.default.documents, count.index)

  depends_on = [
    data.kubectl_path_documents.default
  ]
}

resource "kubectl_manifest" "traefik" {
  count     = length(data.kubectl_path_documents.traefik.documents)
  yaml_body = element(data.kubectl_path_documents.traefik.documents, count.index)

  depends_on = [
    resource.kubectl_manifest.default,
    data.kubectl_path_documents.traefik
  ]
}

resource "kubectl_manifest" "drone" {
  count     = length(data.kubectl_path_documents.drone.documents)
  yaml_body = element(data.kubectl_path_documents.drone.documents, count.index)

  depends_on = [
    resource.kubectl_manifest.traefik,
    data.kubectl_path_documents.drone
  ]
}

resource "kubectl_manifest" "drone_runner" {
  count     = length(data.kubectl_path_documents.drone_runner.documents)
  yaml_body = element(data.kubectl_path_documents.drone_runner.documents, count.index)

  depends_on = [
    resource.kubectl_manifest.traefik,
    data.kubectl_path_documents.drone_runner
  ]
}

resource "helm_release" "minio" {
  name = "minio"
  repository = "https://charts.min.io"
  namespace = "pipeline"
  chart = "minio"

  values      = [
    templatefile("${path.module}/manifest/minio/01-values.yaml", {
      minio_access_key = random_string.minio_access_key.id
      minio_secret_key = random_uuid.minio_secret_key.id
      minio_host = "storage.${data.terraform_remote_state.k3s.outputs.public_domain}"
      minio_console_host = "storage-console.${data.terraform_remote_state.k3s.outputs.public_domain}"
      host = data.terraform_remote_state.k3s.outputs.public_domain
    })
  ]

  depends_on = [
    resource.kubectl_manifest.default,
  ]
}

resource "helm_release" "harbor" {
  name = "harbor"
  repository = "https://helm.goharbor.io"
  namespace = "pipeline"
  chart = "harbor"

  values      = [
    templatefile("${path.module}/manifest/harbor/01-values.yaml", {
      core_host = "registry.${data.terraform_remote_state.k3s.outputs.public_domain}"
      notary_host = "notary.${data.terraform_remote_state.k3s.outputs.public_domain}"
      minio_host = "storage.${data.terraform_remote_state.k3s.outputs.public_domain}"
      minio_access_key = random_string.minio_access_key.id
      minio_secret_key = random_uuid.minio_secret_key.id
      minio_bucket = "registry"
      harbor_admin_password = random_string.harbor_admin_password.id
      harbor_secret_key = random_string.harbor_secret_key.id
    })
  ]

  depends_on = [
    helm_release.minio
  ]
}

resource "kubectl_manifest" "argocd" {
  count     = length(data.kubectl_path_documents.argocd.documents)
  yaml_body = element(data.kubectl_path_documents.argocd.documents, count.index)
  override_namespace = "argocd"

  depends_on = [
    data.kubectl_path_documents.argocd,
    resource.kubectl_manifest.traefik
  ]
}


resource "kubectl_manifest" "ingress" {
  count     = length(data.kubectl_path_documents.ingress.documents)
  yaml_body = element(data.kubectl_path_documents.ingress.documents, count.index)

  depends_on = [
    resource.kubectl_manifest.traefik,
    resource.helm_release.harbor,
    resource.helm_release.minio
  ]
}