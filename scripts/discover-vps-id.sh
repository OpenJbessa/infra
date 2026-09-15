#!/usr/bin/env bash
#
# Découverte automatique de l'ID du VPS Hostinger existant.
#
# Implémente le protocole "external" data source d'OpenTofu/Terraform : lit un
# objet JSON sur stdin (ignoré ici), écrit un objet JSON de chaînes sur stdout.
#
# Principe de sécurité : toute ambiguïté ou erreur sort sur stderr avec un code
# non nul plutôt que de deviner. C'est ce qui transforme un cas limite en échec
# de plan explicite, jamais en commande silencieuse d'un second VPS facturé.
#
# Ne lit AUCUN secret depuis le protocole external (query/result passent par le
# state en clair) : le token est lu directement dans l'environnement, comme
# pour le provider lui-même.
set -euo pipefail

# Le protocole "external" exige de lire stdin, même sans l'utiliser.
cat >/dev/null

API_BASE="${HOSTINGER_API_BASE:-https://developers.hostinger.com}"
TOKEN="${TF_VAR_hostinger_api_token:-}"

fail() {
  echo "$1" >&2
  exit 1
}

[ -n "$TOKEN" ] || fail "TF_VAR_hostinger_api_token n'est pas défini : impossible d'interroger l'API Hostinger."
command -v curl >/dev/null || fail "curl est requis pour la découverte automatique du VPS."
command -v jq >/dev/null || fail "jq est requis pour la découverte automatique du VPS."

# L'API Hostinger a montré des lenteurs/coupures ponctuelles en usage réel :
# quelques tentatives avec backoff avant d'abandonner. Uniquement pour les
# pannes transitoires (timeout, 5xx) — jamais pour un 401/404, que réessayer
# ne résoudra pas.
max_attempts=3
attempt=1
while :; do
  if response=$(curl -sS --max-time 20 -w '\n%{http_code}' \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/json" \
      "$API_BASE/api/vps/v1/virtual-machines" 2>&1); then
    status="${response##*$'\n'}"
    body="${response%$'\n'*}"
    [ "$status" -lt 500 ] 2>/dev/null && break
  fi

  [ "$attempt" -ge "$max_attempts" ] && fail "Échec de connexion à l'API Hostinger après $max_attempts tentatives : ${response:-inconnu}"
  sleep "$((attempt * 2))"
  attempt=$((attempt + 1))
done

[ "$status" = "200" ] || fail "L'API Hostinger a répondu HTTP $status : $body"

echo "$body" | jq -e 'type == "array"' >/dev/null 2>&1 \
  || fail "Réponse de l'API inattendue (pas une liste) : $body"

count=$(echo "$body" | jq 'length')

case "$count" in
0)
  # Aucun VPS : rien à importer, rien à gérer. C'est le défaut sûr.
  echo '{"id": ""}'
  ;;
1)
  id=$(echo "$body" | jq -r '.[0].id // empty')
  [ -n "$id" ] || fail "Réponse de l'API inattendue, aucun champ 'id' exploitable : $body"
  printf '{"id": "%s"}\n' "$id"
  ;;
*)
  ids=$(echo "$body" | jq -c '[.[].id]')
  fail "Plusieurs VPS trouvés ($ids) : la découverte automatique ne peut pas choisir seule. Renseignez existing_vps_id explicitement dans terraform.tfvars pour désambiguïser."
  ;;
esac
