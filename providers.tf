provider "hostinger" {
  api_token = var.hostinger_api_token
}

provider "cloudflare" {
  # Token lu dans la variable d'environnement CLOUDFLARE_API_TOKEN.
  # Permissions requises : Zone — DNS Write, Zone — Zone Read.
}
