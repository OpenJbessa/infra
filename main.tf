resource "hostinger_vps_ssh_key" "this" {
  for_each = var.ssh_keys

  name = each.key
  key  = trimspace(each.value)
}

resource "hostinger_vps_post_install_script" "this" {
  count = var.post_install_script_path != null ? 1 : 0

  name    = var.post_install_script_name
  content = file(var.post_install_script_path)
}

resource "hostinger_vps" "this" {
  count = local.manage_vps ? 1 : 0

  plan           = var.vps_plan
  data_center_id = var.vps_data_center_id
  template_id    = var.vps_template_id

  hostname          = var.vps_hostname
  password          = var.vps_root_password
  payment_method_id = var.vps_payment_method_id

  ssh_key_ids            = [for k in hostinger_vps_ssh_key.this : tonumber(k.id)]
  post_install_script_id = one(hostinger_vps_post_install_script.this[*].id)

  lifecycle {
    # Changer le template réinstalle le VPS et détruit toutes les données.
    # Retirer cette ligne (le temps d'un apply) pour réinstaller volontairement.
    prevent_destroy = true

    precondition {
      condition     = var.vps_root_password == null || length(var.vps_root_password) >= 12
      error_message = "vps_root_password doit faire au moins 12 caractères."
    }
  }
}
