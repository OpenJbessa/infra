// Catalogue Hostinger : sert à découvrir les identifiants à renseigner dans
// terraform.tfvars (vps_plan, vps_data_center_id, vps_template_id).
//
// Désactivé par défaut : ces appels ne servent qu'une fois, et une erreur de
// leur côté ferait échouer tous les `plan`/`apply` de gestion du VPS.
//
//   tofu apply -var enable_catalog=true
//   tofu output catalog_plans

data "hostinger_vps_plans" "all" {
  count = var.enable_catalog ? 1 : 0
}

data "hostinger_vps_data_centers" "all" {
  count = var.enable_catalog ? 1 : 0
}

data "hostinger_vps_templates" "all" {
  count = var.enable_catalog ? 1 : 0
}
