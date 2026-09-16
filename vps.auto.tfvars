# Identifiants du VPS géré par cette configuration.
#
# Versionné volontairement : ce ne sont pas des secrets. Ils sont inexploitables
# sans le token API, fourni par la variable d'environnement
# TF_VAR_hostinger_api_token.
#
# Toute valeur sensible (vps_root_password) va dans terraform.tfvars, gitignoré.
# Chargé automatiquement par OpenTofu grâce au suffixe .auto.tfvars.

# L'ID du VPS n'est plus renseigné ici : il est découvert automatiquement via
# l'API Hostinger (voir discovery.tf). Ne décommenter existing_vps_id que pour
# désambiguïser un compte à plusieurs VPS, ou en environnement sans réseau :
# existing_vps_id = 1977709

vps_plan           = "KVM 2"
vps_data_center_id = 19
vps_template_id    = 1188 # Debian 13 

ssh_keys = {
  "laptop" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBj14mrYL3sBYSJx1/4bEPBq+Y50UbC0J0ywdnX0WyBN"
}

post_install_script_path = "scripts/post-install.sh"

# Contenu envoyé tel quel à Hostinger : défi Cloudflare systématique (voir
# variables.tf). Le stub le remplace, épinglé au dernier commit ayant modifié
# post-install.sh — à mettre à jour après toute modification de ce fichier :
#   git log -1 --format=%H -- scripts/post-install.sh
post_install_fetch_url = "https://raw.githubusercontent.com/OpenJbessa/infra/1eddec77d9a72d129d8351d293d8606de76d97ed/scripts/post-install.sh"
