terraform {
  backend "gcs" {
    # ❗ Crea este bucket antes de hacer "terraform init"
    bucket = "demo-terraform-state-1979"

    # Carpeta lógica dentro del bucket
    prefix = "envs/prod/shared-vpc-gke"

    # (Opcional) Proyecto donde vive el bucket, solo si difiere del host/service project
    # project = "mi-proyecto-de-infra"

    # (Opcional) Encriptación con CMEK
    # encryption_key = "projects/PROJECT_ID/locations/REGION/keyRings/RING/cryptoKeys/KEY"
  }
}