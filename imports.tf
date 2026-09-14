// Reprise d'un VPS déjà commandé.
//
// L'ID vient de la découverte automatique (discovery.tf), ou de
// `existing_vps_id` si renseigné à la main. Le prochain `tofu plan` affiche
// « will be imported » au lieu de « will be created ». Rien n'est créé ni
// facturé, seul l'état Terraform est mis à jour.
//
// Le bloc devient inerte une fois le VPS importé : on peut le laisser en place.

import {
  for_each = local.resolved_vps_id != null ? toset([local.resolved_vps_id]) : toset([])

  to = hostinger_vps.this[0]
  id = each.value
}
