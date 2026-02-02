# Service Account for VMs
resource "google_service_account" "vm_sa" {
  account_id   = "hackathon-vm-sa"
  display_name = "Hackathon VM Service Account"
}

# Allow bucket access for gcsfuse
resource "google_storage_bucket_iam_member" "bucket_access" {
  bucket = var.bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.vm_sa.email}"
}

# Instance Template
resource "google_compute_instance_template" "gpu_template" {
  name_prefix  = "hackathon-gpu-"
  machine_type = "n1-highmem-8"

  disk {
    source_image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
    boot         = true
    disk_size_gb = var.disk_size_gb
  }

  network_interface {
    subnetwork = var.subnet_id
  }

  guest_accelerator {
    type  = "nvidia-tesla-t4"
    count = 1
  }

  service_account {
    email  = google_service_account.vm_sa.email
    scopes = ["cloud-platform"]
  }

  scheduling {
    on_host_maintenance = "TERMINATE"
  }

  # 🔴 REQUIRED for NVIDIA GPU drivers
  shielded_instance_config {
    enable_secure_boot = false
  }

  metadata_startup_script = templatefile(
    "${path.module}/startup_script.sh.tpl",
    {
      bucket_name = var.bucket_name
    }
  )
}

# GPU VMs
resource "google_compute_instance_from_template" "gpu_vms" {
  count                    = 4
  name                     = "hackathon-gpu-${count.index}"
  zone                     = var.zone
  source_instance_template = google_compute_instance_template.gpu_template.id
}
