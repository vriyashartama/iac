terraform {
  required_providers {
    kubectl = {
      source = "gavinbunney/kubectl"
      version = "1.14.0"
    }

    helm = {
      source = "hashicorp/helm"
      version = "2.6.0"
    }

    http = {
      source = "hashicorp/http"
      version = "2.2.0"
    }
  }
}