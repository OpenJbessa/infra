// DNS géré chez Cloudflare, qui sert aussi de proxy devant Traefik.
// Le DNS Hostinger n'est pas utilisé : la zone est déléguée à Cloudflare.

// Interrogée seulement s'il y a des enregistrements à gérer : sans cela, un
// token Cloudflare serait exigé pour toute opération, y compris celles qui ne
// concernent que le VPS.
data "cloudflare_zones" "this" {
  count = length(var.dns_records) > 0 ? 1 : 0

  name = var.cloudflare_zone_name
}

locals {
  cloudflare_zone_id = try(one(data.cloudflare_zones.this[0].result[*].id), null)
}

resource "cloudflare_dns_record" "this" {
  for_each = var.dns_records

  # zone_id est requis par le schéma du provider : lui passer null ferait
  # échouer le plan avec une erreur générique AVANT que la precondition
  # ci-dessous n'ait la main. Le sentinel est rejeté par Cloudflare de toute
  # façon si jamais il était utilisé pour de vrai, mais la precondition bloque
  # toujours le plan avant cet appel.
  zone_id = coalesce(local.cloudflare_zone_id, "zone-cloudflare-introuvable")
  name    = each.value.name == "@" ? var.cloudflare_zone_name : "${each.value.name}.${var.cloudflare_zone_name}"
  type    = each.value.type

  # content omis => adresse du VPS géré ici.
  content = coalesce(
    each.value.content,
    each.value.type == "AAAA" ? local.vps_ipv6 : local.vps_ipv4,
  )

  # ttl = 1 signifie « automatique », seule valeur acceptée quand le proxy est
  # actif : c'est Cloudflare qui répond, pas l'origine.
  ttl     = each.value.proxied ? 1 : each.value.ttl
  proxied = each.value.proxied
  comment = "Géré par OpenTofu"

  lifecycle {
    precondition {
      condition     = each.value.content != null || local.manage_vps
      error_message = "L'enregistrement DNS '${each.key}' n'a pas de `content` et aucun VPS n'est géré : renseignez `content` ou configurez le VPS."
    }

    precondition {
      condition     = local.cloudflare_zone_id != null
      error_message = "Zone Cloudflare '${var.cloudflare_zone_name}' introuvable. Vérifiez le nom du domaine et la permission Zone Read du token."
    }
  }
}
