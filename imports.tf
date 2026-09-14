// Reprise d'un VPS déjà commandé.
//
// Renseigner `existing_vps_id` dans terraform.tfvars : le prochain `tofu plan`
// affiche « will be imported » au lieu de « will be created ». Rien n'est créé
// ni facturé, seul l'état Terraform est mis à jour.
//
// Le bloc devient inerte une fois le VPS importé : on peut le laisser en place.

import {
  for_each = var.existing_vps_id != null ? toset([tostring(var.existing_vps_id)]) : toset([])

  to = hostinger_vps.this[0]
  id = each.value
}
