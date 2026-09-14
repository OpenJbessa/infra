resource "hostinger_dns_record" "this" {
  for_each = var.dns_records

  zone = each.value.zone
  name = each.value.name
  type = each.value.type

  # value omis => on pointe sur l'IP du VPS géré ici.
  value = coalesce(
    each.value.value,
    each.value.type == "AAAA" ? local.vps_ipv6 : local.vps_ipv4,
  )

  ttl       = each.value.ttl
  overwrite = each.value.overwrite

  lifecycle {
    precondition {
      condition     = each.value.value != null || local.manage_vps
      error_message = "L'enregistrement DNS '${each.key}' n'a pas de `value` et aucun VPS n'est géré : renseignez `value` ou configurez le VPS."
    }
  }
}
