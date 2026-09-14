output "state_bucket_name" {
  description = "Nom du bucket R2 créé."
  value       = cloudflare_r2_bucket.state.name
}

output "s3_endpoint" {
  description = "Endpoint compatible S3 à reporter dans le bloc backend de la configuration racine."
  value       = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
}

output "backend_block" {
  description = "Bloc backend prêt à coller dans ../versions.tf."
  value       = <<-EOT
    backend "s3" {
      bucket = "${cloudflare_r2_bucket.state.name}"
      key    = "hostinger/vps.tfstate"
      region = "auto"

      endpoints = { s3 = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com" }

      use_lockfile                = true
      skip_credentials_validation = true
      skip_metadata_api_check     = true
      skip_region_validation      = true
      skip_requesting_account_id  = true
      skip_s3_checksum            = true
    }
  EOT
}
