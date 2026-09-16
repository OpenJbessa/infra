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
vps_template_id    = 1031 # Debian 12 — changé depuis 1188 (Debian 13) pour déclencher une
# réinstallation réelle (Terraform n'agit que sur un changement de
# valeur). Le cahier des charges demande "Debian minimal", sans
# version précise : Debian 12 convient, on y reste pour ne pas
# effacer une seconde fois le cluster fraîchement configuré.

ssh_keys = {
  "laptop" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBj14mrYL3sBYSJx1/4bEPBq+Y50UbC0J0ywdnX0WyBN"
}

post_install_script_path = "scripts/post-install.sh"

# Contenu envoyé tel quel à Hostinger : défi Cloudflare systématique (voir
# variables.tf). Le stub le remplace, épinglé au dernier commit ayant modifié
# post-install.sh — à mettre à jour après toute modification de ce fichier :
#   git log -1 --format=%H -- scripts/post-install.sh
post_install_fetch_url = "https://raw.githubusercontent.com/OpenJbessa/infra/ef42b88372c113d9ebea5f6fa2a2ffe596ff447d/scripts/post-install.sh"
