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

Reportez les valeurs dans `terraform.tfvars`, puis laissez `enable_catalog` à
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
> commanderiez un second VPS. Vérifiez la valeur dans `terraform.tfvars`.

Si le second `tofu plan` n'est pas vide, alignez `terraform.tfvars` sur ce que
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

### Clés SSH

```hcl
ssh_keys = {
  "laptop" = "ssh-ed25519 AAAAC3... jonathan@laptop"
}
```

Elles sont enregistrées chez Hostinger et attachées au VPS.

### DNS

Le DNS est géré **chez Cloudflare**, qui sert aussi de proxy devant Traefik. Le
DNS Hostinger n'est pas utilisé.

Un enregistrement sans `content` pointe automatiquement sur l'IP du VPS géré ici
(IPv4 pour un `A`, IPv6 pour un `AAAA`). `name` est relatif à la zone :

```hcl
dns_records = {
  apex    = { name = "@", type = "A" }
  grafana = { name = "grafana", type = "A" }
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

`post_install_script_path = "scripts/post-install.sh"` enregistre le script chez
Hostinger et le rattache au VPS. Il amorce le nœud : utilisateur non privilégié,
nftables en refus par défaut, mises à jour de sécurité, et K3s avec Traefik
désactivé, chiffrement des Secrets et réservations kubelet.

> ⚠️ **Aucun secret ne doit y figurer.** Le script est stocké chez l'hébergeur
> et consultable depuis son interface : ni clé age, ni jeton Teleport, ni
> identifiants R2. Tout le reste entre par ArgoCD.

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
