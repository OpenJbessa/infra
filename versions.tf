terraform {
  required_version = ">= 1.6"

  required_providers {
    hostinger = {
      source  = "hostinger/hostinger"
      version = "~> 0.1.23"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.25"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }

  # État LOCAL pour le moment (choix délibéré, pas une étape en attente :
  # activer R2 suppose un moyen de paiement sur le compte Cloudflare, même
  # pour le palier gratuit). Rien ci-dessous n'est requis pour travailler.
  #
  # Le jour où c'est utile : bootstrap/ crée le bucket (voir
  # bootstrap/README.md), verrouillé par use_lockfile (écriture conditionnelle
  # If-None-Match, sans table DynamoDB). Remplacer <account_id> ci-dessous,
  # décommenter, puis migrer l'état local existant :
  #
  #   export AWS_ACCESS_KEY_ID=...        # jeton R2, pas le token Cloudflare
  #   export AWS_SECRET_ACCESS_KEY=...
  #   tofu init -migrate-state
  #
  # ATTENTION : l'état contient le token API et le mot de passe root en clair.
  # Le bucket ne doit jamais être public.
  #
  # backend "s3" {
  #   bucket = "jbessa-tfstate"
  #   key    = "hostinger/vps.tfstate"
  #   region = "auto"
  #
  #   endpoints = { s3 = "https://<account_id>.r2.cloudflarestorage.com" }
  #
  #   use_lockfile = true
  #
  #   # R2 n'implémente ni STS, ni l'API de métadonnées EC2, ni les sommes de
  #   # contrôle S3 : ces vérifications doivent être désactivées.
  #   skip_credentials_validation = true
  #   skip_metadata_api_check     = true
  #   skip_region_validation      = true
  #   skip_requesting_account_id  = true
  #   skip_s3_checksum            = true
  # }
}
