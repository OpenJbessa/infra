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

    # Bug connu et non résolu du provider (upstream, pas notre code) :
    # https://github.com/hostinger/terraform-provider-hostinger/issues/29
    # La route API que le provider appelle pour vérifier les clés déjà
    # attachées avant d'en ajouter une nouvelle (GET .../public-keys) renvoie
    # 404 côté Hostinger. Documenté comme cassé par d'autres utilisateurs.
    #
    # Conséquence : ajouter une entrée à `ssh_keys` continue d'enregistrer la
    # clé chez Hostinger (hostinger_vps_ssh_key, non affecté), mais l'attacher
    # à CE VPS doit se faire à la main dans le hPanel — Terraform n'essaiera
    # plus de le faire tout seul. Retirer cette ligne le jour où l'upstream
    # corrige la route.
    ignore_changes = [ssh_key_ids]

    precondition {
      condition     = var.vps_root_password == null || length(var.vps_root_password) >= 12
      error_message = "vps_root_password doit faire au moins 12 caractères."
    }

    # Garde-fou financier : si la découverte automatique de l'ID (discovery.tf)
    # échoue silencieusement ou renvoie « aucun VPS trouvé » alors qu'un abonnement
    # existe déjà, ce précondition bloque l'apply au lieu d'en commander un second.
    precondition {
      condition     = local.resolved_vps_id != null || var.confirm_new_vps_order
      error_message = "Aucun VPS existant détecté (ni découverte automatique, ni existing_vps_id) : appliquer commanderait un NOUVEAU VPS facturé chez Hostinger. Si un VPS existe déjà, vérifiez TF_VAR_hostinger_api_token et la sortie de `tofu plan` avant de continuer. Pour confirmer une commande volontaire, positionnez confirm_new_vps_order = true."
    }
  }
}
