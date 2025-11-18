terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source = "hashicorp/google"
      # Acepta cualquier 7.x
      version = ">= 7.0.0, < 8.0.0"
    }

    # Muchos módulos de GKE usan google-beta por debajo;
    # es buena idea declararlo explícitamente con la misma constraint.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 7.0.0, < 8.0.0"
    }

    # Opcional, pero recomendable dejar fijas estas también
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.10"
    }
  }
}