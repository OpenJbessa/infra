variable "hostinger_api_token" {
  description = "Token API Hostinger. À fournir via la variable d'environnement TF_VAR_hostinger_api_token, jamais en dur dans un fichier versionné."
  type        = string
  sensitive   = true
}

# --- Catalogue ---------------------------------------------------------------

variable "enable_catalog" {
  description = "Interroge l'API pour lister plans, datacenters et templates disponibles (outputs `catalog_*`). À activer le temps de trouver les identifiants, puis à laisser désactivé : cela évite que ces appels fassent échouer les apply courants."
  type        = bool
  default     = false
}

# --- VPS ---------------------------------------------------------------------
# Tant que vps_plan / vps_data_center_id / vps_template_id valent null, aucune
# ressource VPS n'est gérée : on peut lancer `tofu plan` pour lire le catalogue
# (voir outputs.tf) sans risquer de commander un serveur.

variable "vps_plan" {
  description = "Identifiant du plan VPS (ex. hostingercom-vps-kvm2-usd-1m). Voir l'output `catalog_plans`. null = pas de VPS géré."
  type        = string
  default     = null
}

variable "vps_data_center_id" {
  description = "ID du datacenter. Voir l'output `catalog_data_centers`."
  type        = number
  default     = null
}

variable "vps_template_id" {
  description = "ID du template OS à installer (ex. 1002 pour Debian 11). Voir l'output `catalog_templates`."
  type        = number
  default     = null
}

variable "existing_vps_id" {
  description = "ID d'un VPS déjà commandé à reprendre sous gestion Terraform. Laissé à null (recommandé), l'ID est découvert automatiquement via l'API Hostinger (scripts/discover-vps-id.sh). Ne le renseigner à la main que pour désambiguïser un compte à plusieurs VPS, ou dans un environnement sans accès réseau à l'API. Dans tous les cas, exige que vps_plan / vps_data_center_id / vps_template_id soient également renseignés."
  type        = number
  default     = null
}

variable "confirm_new_vps_order" {
  description = "Garde-fou financier. Doit être positionné à true explicitement pour commander un NOUVEAU VPS facturé, lorsque ni la découverte automatique ni existing_vps_id ne trouvent de VPS existant alors que vps_plan/vps_data_center_id/vps_template_id sont renseignés. Empêche une commande accidentelle si la découverte échoue silencieusement (jeton invalide, panne réseau, etc.)."
  type        = bool
  default     = false
}

variable "vps_hostname" {
  description = "FQDN à assigner au VPS. null = Hostinger en génère un."
  type        = string
  default     = null
}

variable "vps_root_password" {
  description = "Mot de passe root initial. null = généré par Hostinger. Préférer l'accès par clé SSH."
  type        = string
  default     = null
  sensitive   = true
}

variable "vps_payment_method_id" {
  description = "ID du moyen de paiement à utiliser pour la commande. null = moyen par défaut du compte."
  type        = number
  default     = null
}

# --- Clés SSH ----------------------------------------------------------------

variable "ssh_keys" {
  description = "Clés SSH publiques à enregistrer chez Hostinger et à attacher au VPS. Clé de la map = nom affiché, valeur = contenu de la clé publique."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k in values(var.ssh_keys) : can(regex("^(ssh-(rsa|ed25519|dss)|ecdsa-sha2-) ", k))])
    error_message = "Chaque valeur doit être une clé publique OpenSSH (ssh-ed25519 AAAA..., ssh-rsa AAAA..., ecdsa-sha2-...)."
  }
}

# --- Script de post-installation ---------------------------------------------

variable "post_install_script_path" {
  description = "Chemin d'un script shell exécuté après l'installation de l'OS (voir scripts/post-install.sh). null = aucun script. Ne s'exécute qu'à la création/réinstallation du VPS, pas à chaque apply."
  type        = string
  default     = null
}

variable "post_install_script_name" {
  description = "Nom affiché du script de post-installation dans le panel Hostinger."
  type        = string
  default     = "terraform-post-install"
}

# --- DNS ---------------------------------------------------------------------

variable "cloudflare_zone_name" {
  description = "Domaine géré chez Cloudflare (ex. jbessa.tech). La zone y est déléguée ; le DNS Hostinger n'est pas utilisé."
  type        = string
}

variable "dns_records" {
  description = "Enregistrements DNS à gérer dans la zone Cloudflare. `name` est relatif à la zone (`@` pour l'apex). Laisser `content` à null pour pointer automatiquement sur l'IPv4 du VPS (type A) ou son IPv6 (type AAAA)."
  type = map(object({
    name    = string
    type    = string
    content = optional(string)
    proxied = optional(bool, true)
    ttl     = optional(number, 1)
  }))
  default = {}

  validation {
    condition = alltrue([
      for r in values(var.dns_records) :
      r.content != null || contains(["A", "AAAA"], r.type)
    ])
    error_message = "`content` ne peut être omis que pour les enregistrements de type A ou AAAA (il est alors déduit de l'IP du VPS)."
  }

  validation {
    condition = alltrue([
      for r in values(var.dns_records) :
      !r.proxied || contains(["A", "AAAA", "CNAME"], r.type)
    ])
    error_message = "Seuls les enregistrements A, AAAA et CNAME peuvent être proxifiés par Cloudflare."
  }
}
