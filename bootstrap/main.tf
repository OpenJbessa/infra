resource "cloudflare_r2_bucket" "state" {
  account_id    = var.cloudflare_account_id
  name          = var.state_bucket_name
  location      = var.state_bucket_location
  storage_class = "Standard"

  lifecycle {
    # Détruire ce bucket emporterait l'état de toute l'infrastructure.
    prevent_destroy = true
  }
}
