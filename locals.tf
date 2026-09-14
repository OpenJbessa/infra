locals {
  # Un VPS n'est géré que si le trio plan / datacenter / template est renseigné.
  manage_vps = var.vps_plan != null && var.vps_data_center_id != null && var.vps_template_id != null

  # Extraction par splat plutôt que sur l'objet entier : celui-ci porte le
  # `password` sensible, dont la marque contaminerait tous les outputs.
  vps_ipv4 = one(hostinger_vps.this[*].ipv4_address)
  vps_ipv6 = one(hostinger_vps.this[*].ipv6_address)
}
