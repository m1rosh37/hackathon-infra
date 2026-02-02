variable "subnet_id" {
  type = string
}

variable "zone" {
  type = string
}

variable "bucket_name" {
  type = string
}

variable "disk_size_gb" {
  type    = number
  default = 256
}
