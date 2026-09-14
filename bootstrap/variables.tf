variable "cloudflare_account_id" {
  description = "Identifiant du compte Cloudflare (tableau de bord R2, colonne de droite, ou `wrangler whoami`)."
  type        = string
}

variable "state_bucket_name" {
  description = "Nom du bucket R2 hébergeant l'état OpenTofu de la configuration racine."
  type        = string
  default     = "jbessa-tfstate"
}

variable "state_bucket_location" {
  description = "Indication de localisation du bucket. weur = Europe de l'Ouest. N'est honorée qu'à la première création."
  type        = string
  default     = "weur"

  validation {
    condition     = contains(["apac", "eeur", "enam", "weur", "wnam", "oc"], var.state_bucket_location)
    error_message = "Localisation invalide : apac, eeur, enam, weur, wnam ou oc."
  }
}
