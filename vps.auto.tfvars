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
