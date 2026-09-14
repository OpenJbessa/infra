terraform {
  required_version = ">= 1.6"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.25"
    }
  }

  # État LOCAL, volontairement.
  #
  # Ce module crée le bucket qui héberge l'état de la configuration racine : il
  # ne peut donc pas s'y stocker lui-même. C'est l'amorçage assumé du projet.
  #
  # Cet état est jetable : le bucket se réimporte en une commande (voir README).
  # Il est gitignoré car il contient l'identifiant de compte Cloudflare.
}

provider "cloudflare" {
  # Token lu dans la variable d'environnement CLOUDFLARE_API_TOKEN.
  # Permission requise : Workers R2 Storage — Write.
}
