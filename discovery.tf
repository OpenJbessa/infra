// Découverte automatique de l'ID du VPS existant, pour l'import de main.tf.
//
// Ignorée si existing_vps_id est renseigné à la main (utile en CI sans accès
// réseau à l'API Hostinger, ou pour désambiguïser un compte à plusieurs VPS).

data "external" "vps" {
  count = var.existing_vps_id == null ? 1 : 0

  program = ["bash", "${path.module}/scripts/discover-vps-id.sh"]
}

locals {
  # "" est le sentinel du script pour « aucun VPS trouvé ».
  discovered_vps_id = try(one(data.external.vps[*].result.id), "")

  resolved_vps_id = (
    var.existing_vps_id != null
    ? tostring(var.existing_vps_id)
    : (local.discovered_vps_id != "" ? local.discovered_vps_id : null)
  )
}
