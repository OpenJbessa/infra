# IaC — VPS Hostinger

Configuration Terraform / OpenTofu pour gérer un VPS Hostinger : le serveur lui-même,
les clés SSH, le script de post-installation et les enregistrements DNS.

Provider : [`hostinger/hostinger`](https://registry.terraform.io/providers/hostinger/hostinger/latest/docs) `~> 0.1.23`.

## Prérequis

- OpenTofu ≥ 1.6 (ou Terraform ≥ 1.6)
- Un token API Hostinger : *hPanel → Compte → API → Générer un token*
- `curl` et `jq` dans le `PATH` — utilisés par
  [scripts/discover-vps-id.sh](scripts/discover-vps-id.sh) pour la découverte
  automatique de l'ID du VPS

`.terraform.lock.hcl` a été généré par OpenTofu et référence `registry.opentofu.org`.
Si vous basculez sur Terraform, supprimez-le et relancez `terraform init`.

## Le token API

Il ne doit jamais être écrit dans un fichier versionné. Exportez-le :

```bash
export TF_VAR_hostinger_api_token="hst_..."
```

Pour le rendre persistant sans le committer, mettez cette ligne dans un fichier
`.envrc` (gitignoré, à charger avec [direnv](https://direnv.net/)) ou dans votre
gestionnaire de secrets.

## Où vont les valeurs

| Fichier | Versionné | Contenu |
|---|---|---|
| `vps.auto.tfvars` | ✅ oui | Plan, datacenter et template du VPS. Ce ne sont pas des secrets — ils sont inexploitables sans le token. L'ID du VPS n'y figure pas : il est découvert automatiquement. |
| `cloudflare.auto.tfvars` | ✅ oui | La zone DNS gérée. |
| `terraform.tfvars` | ❌ non | Tout ce qui est sensible, `vps_root_password` en tête. |
| variables d'environnement | ❌ non | `TF_VAR_hostinger_api_token`, `CLOUDFLARE_API_TOKEN`. Les identifiants R2 (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) ne servent que le jour où l'état distant est activé — voir plus bas. |

Les deux fichiers sont chargés automatiquement. En cas de doublon,
`*.auto.tfvars` l'emporte sur `terraform.tfvars` — ne déclarez donc pas la même
variable dans les deux.

## Démarrage

L'état est **local pour le moment** (`terraform.tfstate`, gitignoré) : c'est un
choix délibéré, pas une étape à finir. Un backend distant sur Cloudflare R2 est
prêt dans [bootstrap/](bootstrap/) pour le jour où c'est utile — voir
« État distant » plus bas — mais rien ne l'exige pour travailler.

```bash
tofu init
```

Tant que `vps_plan`, `vps_data_center_id` et `vps_template_id` ne sont pas
renseignés, **aucune ressource VPS n'est gérée** — `tofu apply` ne commande donc
rien par accident.

### 1. Trouver les identifiants

> Pour reprendre un VPS existant, sautez cette étape : la requête de l'étape 2a
> renvoie déjà le plan, le datacenter et le template du serveur.

```bash
tofu apply -var enable_catalog=true
tofu output catalog_plans
tofu output catalog_data_centers
tofu output catalog_templates
```

Reportez les valeurs dans `vps.auto.tfvars`, puis laissez `enable_catalog` à
`false` pour la suite (ces appels ne servent plus, et les garder actifs ajoute un
point de panne à chaque `apply`).

### 2a. Reprendre un VPS existant (import automatique)

C'est le chemin à suivre si le VPS est déjà commandé : l'import le place sous
gestion Terraform **sans rien recréer ni facturer**.

**L'ID du VPS est découvert automatiquement** ([discovery.tf](discovery.tf)) :
à chaque `plan`, [scripts/discover-vps-id.sh](scripts/discover-vps-id.sh)
interroge l'API Hostinger, et s'il n'existe qu'un seul VPS sur le compte, son ID
alimente directement le bloc `import` de [imports.tf](imports.tf). Rien à copier
à la main.

Il reste à renseigner `vps_plan`, `vps_data_center_id` et `vps_template_id` dans
`vps.auto.tfvars` — ces trois-là ne sont pas devinés, volontairement (voir
« Pourquoi seul l'ID est deviné » ci-dessous) :

```bash
curl -s -H "Authorization: Bearer $TF_VAR_hostinger_api_token" \
  https://developers.hostinger.com/api/vps/v1/virtual-machines | jq
```

```hcl
vps_plan           = "KVM 2"
vps_data_center_id = 13
vps_template_id    = 1002
```

```bash
tofu plan    # doit annoncer "1 to import" — jamais "1 to add"
tofu apply
tofu plan    # doit annoncer "No changes"
```

#### Garde-fou financier

Si `vps_plan`/`vps_data_center_id`/`vps_template_id` sont renseignés mais
qu'**aucun VPS n'est trouvé** (compte vide, jeton invalide, panne réseau vers
l'API Hostinger), le `plan` **échoue au lieu de commander un nouveau VPS** :

```
Error: Resource precondition failed
Aucun VPS existant détecté (ni découverte automatique, ni existing_vps_id) : appliquer
commanderait un NOUVEAU VPS facturé chez Hostinger. [...] Pour confirmer une commande
volontaire, positionnez confirm_new_vps_order = true.
```

Face à cette erreur, **cherchez d'abord pourquoi** (token, réseau) avant de
songer à passer outre. `confirm_new_vps_order = true` n'a de sens que pour
commander un second VPS *en toute connaissance de cause* (voir 2b).

Si le compte a **plusieurs VPS**, la découverte automatique refuse de choisir et
le `plan` échoue avec la liste de leurs ID — renseignez alors `existing_vps_id`
à la main pour désigner celui à gérer ici ; cela court-circuite aussi la
découverte (aucun appel réseau), utile en CI sans accès à l'API Hostinger.

```hcl
existing_vps_id = 123456
```

#### Pourquoi seul l'ID est deviné

L'API renvoie le plan sous son nom lisible (`"KVM 2"`, pas le SKU de commande),
et rien ne garantit que sa forme soit identique entre l'endpoint de liste et
celui consulté par le `refresh` du provider pour un VPS donné. Reconstituer
`vps_plan`/`vps_data_center_id`/`vps_template_id` par API interposée risquerait
un faux « to change » à chaque `plan`. L'ID, lui, est un entier sans ambiguïté :
c'est la seule valeur que la découverte automatique se permet de déduire.

> ⚠️ Si le plan annonce `will be created` au lieu de `will be imported`, c'est
> qu'`existing_vps_id` n'est pas pris en compte. **N'appliquez pas** : vous
> commanderiez un second VPS. Vérifiez la valeur dans `vps.auto.tfvars`.

Si le second `tofu plan` n'est pas vide, alignez `vps.auto.tfvars` sur ce que
le plan affiche — c'est la réalité du serveur. Deux écarts fréquents :

- **Clés SSH** : le VPS en a déjà, mais `ssh_keys` est vide → le plan propose de
  les détacher. Déclarez-les dans `ssh_keys`, ou ajoutez
  `ignore_changes = [ssh_key_ids]` au bloc `lifecycle` de [main.tf](main.tf).
- **`hostname`** : laissez `vps_hostname` à `null` pour conserver celui du
  serveur.

### 2b. Commander un nouveau VPS

⚠️ **`tofu apply` avec `vps_plan` renseigné passe une commande payante chez
Hostinger.** Relisez toujours le plan avant de confirmer.

```bash
tofu plan -out=tf.plan
tofu apply tf.plan
tofu output vps_ssh_command
```

## État distant (plus tard)

Pour l'instant, l'état reste **local**, par choix : activer R2 suppose de mettre
un moyen de paiement sur le compte Cloudflare, même pour rester dans le palier
gratuit, et ce n'est pas le moment.

Rien à faire aujourd'hui. Le jour où c'est utile — travailler depuis une autre
machine, une CI, ou simplement sécuriser l'état — [bootstrap/](bootstrap/)
crée le bucket R2 et [versions.tf](versions.tf) contient le bloc `backend`
prêt à décommenter. La marche à suivre est dans
[bootstrap/README.md](bootstrap/README.md).

En attendant, seul filet de sécurité : **`terraform.tfstate` ne vit que sur
cette machine**, sans copie ailleurs. Il n'est pas nécessaire de le sauvegarder
activement — si la machine est perdue, le VPS continue de tourner chez
Hostinger, il suffit de le réimporter (section 2a) pour reprendre la main.

## Ce qui est géré

| Fichier | Contenu |
|---|---|
| [versions.tf](versions.tf) | Versions requises, backend R2 (différé, voir plus haut) |
| [providers.tf](providers.tf) | Providers Hostinger et Cloudflare |
| [variables.tf](variables.tf) | Toutes les entrées |
| [locals.tf](locals.tf) | Valeurs dérivées |
| [main.tf](main.tf) | VPS, clés SSH, script de post-installation |
| [data.tf](data.tf) | Catalogue plans / datacenters / templates (optionnel) |
| [dns.tf](dns.tf) | Enregistrements DNS Cloudflare |
| [outputs.tf](outputs.tf) | IP, statut, commande SSH, catalogue |
| [discovery.tf](discovery.tf) | Découverte automatique de l'ID du VPS existant |
| [imports.tf](imports.tf) | Reprise du VPS existant |
| [scripts/post-install.sh](scripts/post-install.sh) | Bootstrap du nœud : utilisateur, nftables, K3s |
| [bootstrap/](bootstrap/) | Création du bucket R2 hébergeant l'état distant |
| [.github/workflows/opentofu.yml](.github/workflows/opentofu.yml) | CI : fmt, validate, scan, plan |

## CI — GitHub Actions

La pipeline ([.github/workflows/opentofu.yml](.github/workflows/opentofu.yml))
valide et prévisualise à chaque pull request : `tofu fmt`, `tofu validate`, un
scan de sécurité ([Trivy](https://github.com/aquasecurity/trivy)) et `tofu
plan`, dont le résultat est posté en commentaire sur la PR. Un run
hebdomadaire (planifié) rejoue le même plan pour détecter une dérive — un
changement fait à la main dans le hPanel, par exemple.

**Elle n'exécute jamais `apply`.** Avec l'état encore local (voir « État
distant » plus haut), des runners éphémères qui appliqueraient en parallèle
recréeraient la clé SSH et le script post-install en double au lieu de
converger — ces deux ressources ne bénéficient pas de la découverte
automatique du VPS. `apply` reste une action humaine délibérée jusqu'à ce que
l'état soit distant et verrouillé.

### Secret à configurer

Un seul, sur *Settings → Secrets and variables → Actions → New repository
secret* :

| Nom | Valeur |
|---|---|
| `HOSTINGER_API_TOKEN` | Le même token que `TF_VAR_hostinger_api_token` en local |

`vps_plan`, `vps_data_center_id`, `vps_template_id` etc. **ne sont pas des
secrets** : ils restent dans `vps.auto.tfvars`, versionnés et lisibles dans les
diffs de PR — c'est tout l'intérêt de l'IaC. Les y déplacer les rendrait
invisibles aux revues sans le moindre gain de sécurité, puisqu'ils sont déjà
publics dans le dépôt.

Si `dns_records` est renseigné un jour, la CI aura aussi besoin de
`CLOUDFLARE_API_TOKEN` (mêmes permissions qu'en local) pour que le plan
résolve la zone.

### Clés SSH

```hcl
ssh_keys = {
  "laptop" = "ssh-ed25519 AAAAC3... jonathan@laptop"
}
```

Chaque entrée est enregistrée chez Hostinger (`hostinger_vps_ssh_key`).

> ⚠️ **L'attache automatique au VPS est cassée côté Hostinger** —
> [issue #29](https://github.com/hostinger/terraform-provider-hostinger/issues/29),
> ouverte, non résolue. La route API que le provider appelle pour vérifier les
> clés déjà attachées avant d'en ajouter une renvoie 404. `ignore_changes` sur
> `ssh_key_ids` ([main.tf](main.tf)) empêche que ça bloque les `plan` suivants,
> mais en conséquence **une nouvelle clé ajoutée ici est enregistrée chez
> Hostinger, jamais attachée automatiquement à ce VPS** : il faut le faire à la
> main dans le hPanel (*VPS → srv1977709.hstgr.cloud → Clés SSH*) après chaque
> `apply` qui en ajoute une. Retirer `ignore_changes` le jour où l'upstream
> corrige la route.

### DNS

Le DNS est géré **chez Cloudflare**, qui sert aussi de proxy devant Traefik. Le
DNS Hostinger n'est pas utilisé.

Un enregistrement sans `content` pointe automatiquement sur l'IP du VPS géré ici
(IPv4 pour un `A`, IPv6 pour un `AAAA`). `name` est relatif à la zone :

```hcl
dns_records = {
  apex     = { name = "@", type = "A" }
  grafana  = { name = "grafana", type = "A" }
  teleport = { name = "teleport", type = "A", proxied = false }
}
```

`proxied` vaut `true` par défaut : le trafic passe par Cloudflare, qui masque
l'adresse d'origine. Le `ttl` est alors forcé à « automatique », seule valeur
acceptée derrière le proxy.

Mettez `proxied = false` pour tout ce qui n'est pas du HTTP(S) classique —
Teleport notamment. Le token Cloudflare doit porter les permissions *Zone — DNS
Write* et *Zone — Zone Read* :

```bash
export CLOUDFLARE_API_TOKEN="..."
```

Tant que `dns_records` est vide, la zone n'est pas interrogée et aucun token
Cloudflare n'est nécessaire.

### Script de post-installation

`post_install_script_path = "scripts/post-install.sh"` pointe vers le script qui
amorce le nœud : utilisateur non privilégié, nftables en refus par défaut, mises
à jour de sécurité, et K3s avec Traefik désactivé, chiffrement des Secrets et
réservations kubelet.

> ⚠️ **Aucun secret ne doit y figurer.** Le script devient public (voir
> ci-dessous) et est de toute façon consultable depuis l'interface Hostinger :
> ni clé age, ni jeton Teleport, ni identifiants R2. Tout le reste entre par
> ArgoCD.

#### Pourquoi un stub plutôt que le fichier envoyé tel quel

Le contenu n'est **plus envoyé directement** à l'API Hostinger. Soumis en une
fois, ce script (250 lignes : sudoers, durcissement SSH, unités systemd,
pare-feu, installation K3s) fait systématiquement échouer sa création avec un
défi Cloudflare — `Error: failed to create post-install script: ... Just a
moment...`, la page JS que l'API sert quand Cloudflare protège
`developers.hostinger.com`.

Isolé par dichotomie (script coupé en deux, quatre, seize, jusqu'à des
fragments de quelques lignes, une quinzaine de tentatives) : **aucun motif
textuel précis n'explique le blocage**. Un même bloc de durcissement SSH échoue
qu'il soit en clair, en base64, ou remplacé par un contenu factice ; d'autres
moitiés du script, tout aussi denses, passent sans problème. Le seul dénominateur
commun : le script complet échoue systématiquement (y compris après plusieurs
heures d'attente, ce qui exclut un simple throttling temporaire), alors que
tout fragment assez court passe. Conclusion la plus probable : un score WAF
cumulatif sur l'ensemble du contenu (plusieurs motifs modérément sensibles —
sudoers, SSH, systemd, pare-feu — qui s'additionnent), pas un motif unique.

`post_install_fetch_url` (dans [variables.tf](variables.tf)) est le contournement :
un stub de quelques lignes, largement sous ce seuil, est ce qui est réellement
envoyé à Hostinger. Il télécharge le vrai script depuis GitHub (dépôt public,
sans secret — c'est pour ça qu'il doit rester sans secret) et l'exécute :

```hcl
post_install_fetch_url = "https://raw.githubusercontent.com/OpenJbessa/infra/<commit>/scripts/post-install.sh"
```

**À refaire après toute modification de `post-install.sh`** — le commit épinglé
fige le contenu réellement exécuté au boot, y compris pour d'anciennes
attaches déjà en state :

```bash
git push
git log -1 --format=%H -- scripts/post-install.sh   # commit à coller dans l'URL ci-dessus
```

Si le commit ciblé n'est pas poussé, `tofu apply` réussit quand même (Hostinger
stocke le stub sans jamais vérifier que l'URL répond) — l'échec n'apparaît qu'au
boot du VPS, silencieusement (`curl -f` fait échouer le stub, le nœud reste nu).
**Vérifier avant d'appliquer** :

```bash
curl -s -o /dev/null -w "%{http_code}\n" "$(echo 'var.post_install_fetch_url' | tofu console | tr -d '\"')"
# doit répondre 200
```

Il ne s'exécute qu'à la **création ou la réinstallation** du serveur. Modifier le
fichier ne reconfigure pas un VPS déjà en place : l'attacher est un
`update in-place`, mais Hostinger ne le rejoue qu'à l'installation de l'OS.

**Pour le rejouer, changez `vps_template_id`** — c'est aussi un `update in-place`
et non une destruction, donc l'abonnement n'est pas résilié. C'est le mécanisme
de reconstruction du projet. Il efface le disque.

Le pare-feu n'ouvre 80 et 443 qu'aux plages Cloudflare, rafraîchies chaque jour
par un timer systemd plutôt que figées à l'installation. Le port 22 reste ouvert
jusqu'à la bascule sur Teleport.

## Points d'attention

- **Le state contient des secrets en clair** (token API, mot de passe root).
  `.gitignore` l'exclut. Il est local pour l'instant — voir « État distant »
  plus haut.
- **`prevent_destroy = true`** protège le VPS dans [main.tf](main.tf). Pour le
  détruire ou le réinstaller volontairement, commentez cette ligne le temps d'un
  `apply`. Changer `vps_template_id` réinstalle l'OS et **efface les données**.
- **Portée du provider** : il ne couvre que le VPS, les clés SSH, les scripts de
  post-installation et le DNS. Pas de pare-feu, de snapshots ni de sauvegardes —
  cela reste à faire dans le hPanel ou sur le serveur.
- **`tofu destroy` résilie l'abonnement** du VPS. L'abonnement Hostinger actuel
  est **mensuel** (KVM 2) : contrairement à un prépayé annuel, résilier n'efface
  pas un crédit déjà versé, mais arrête la reconduction — vérifiez la date de
  fin de période en cours avant de détruire, pour ne pas payer un mois entamé
  pour rien.
- **La découverte automatique de l'ID VPS** ([discovery.tf](discovery.tf))
  interroge l'API Hostinger à chaque `plan`. Un garde-fou
  (`confirm_new_vps_order`) empêche qu'un échec silencieux de cette découverte
  ne commande un second VPS facturé — détails dans la section 2a.
