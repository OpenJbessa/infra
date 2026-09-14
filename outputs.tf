# --- VPS ---------------------------------------------------------------------

output "vps_id" {
  description = "ID Hostinger du VPS."
  value       = one(hostinger_vps.this[*].vps_id)
}

output "vps_hostname" {
  description = "FQDN du VPS."
  value       = one(hostinger_vps.this[*].hostname)
}

output "vps_ipv4" {
  description = "Adresse IPv4 publique du VPS."
  value       = local.vps_ipv4
}

output "vps_ipv6" {
  description = "Adresse IPv6 publique du VPS."
  value       = local.vps_ipv6
}

output "vps_status" {
  description = "État courant du VPS (running, stopped, installing...)."
  value       = one(hostinger_vps.this[*].status)
}

output "vps_ssh_command" {
  description = "Commande prête à l'emploi pour se connecter au VPS."
  value       = local.vps_ipv4 == null ? null : "ssh root@${local.vps_ipv4}"
}

output "ssh_key_ids" {
  description = "IDs Hostinger des clés SSH gérées ici, par nom."
  value       = { for name, k in hostinger_vps_ssh_key.this : name => k.id }
}

# --- Catalogue ---------------------------------------------------------------

# Renseignés uniquement avec `-var enable_catalog=true`.

output "catalog_plans" {
  description = "Plans VPS disponibles (à utiliser pour vps_plan)."
  value       = one(data.hostinger_vps_plans.all[*].plans)
}

output "catalog_data_centers" {
  description = "Datacenters disponibles (à utiliser pour vps_data_center_id)."
  value       = one(data.hostinger_vps_data_centers.all[*].data_centers)
}

output "catalog_templates" {
  description = "Templates OS disponibles (à utiliser pour vps_template_id)."
  value       = one(data.hostinger_vps_templates.all[*].templates)
}
