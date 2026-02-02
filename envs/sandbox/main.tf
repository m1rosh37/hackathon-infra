provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

module "network" {
  source = "../../modules/network"
  region = var.region
}

module "storage" {
  source      = "../../modules/storage"
  bucket_name = "hackathon-sandbox-${var.project_id}"
  region      = var.region
}

module "gpu-compute" {
  source      = "../../modules/gpu-compute"
  subnet_id   = module.network.subnet_id
  zone        = var.zone
  bucket_name = module.storage.bucket_name
}
