# IaC — VPS Hostinger

Configuration Terraform / OpenTofu pour gérer un VPS Hostinger : le serveur lui-même,
les clés SSH, le script de post-installation et les enregistrements DNS.

Provider : [`hostinger/hostinger`](https://registry.terraform.io/providers/hostinger/hostinger/latest/docs) `~> 0.1.23`.

## Prérequis

- OpenTofu ≥ 1.6 (ou Terraform ≥ 1.6)
- Un token API Hostinger : *hPanel → Compte → API → Générer un token*

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
| `vps.auto.tfvars` | ✅ oui | Identifiants du VPS : `existing_vps_id`, plan, datacenter, template. Ce ne sont pas des secrets — ils sont inexploitables sans le token. |
| `terraform.tfvars` | ❌ non | Tout ce qui est sensible, `vps_root_password` en tête. |
| variable d'environnement | ❌ non | Le token API. |

Les deux fichiers sont chargés automatiquement. En cas de doublon,
`*.auto.tfvars` l'emporte sur `terraform.tfvars` — ne déclarez donc pas la même
variable dans les deux.

## Démarrage

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

### 2a. Reprendre un VPS existant (import)

C'est le chemin à suivre si le VPS est déjà commandé : l'import le place sous
gestion Terraform **sans rien recréer ni facturer**.

Relevez d'abord son ID et ses caractéristiques — cette requête renvoie tout ce
qu'il faut d'un coup, et vaut test du token :

```bash
curl -s -H "Authorization: Bearer $TF_VAR_hostinger_api_token" \
  https://developers.hostinger.com/api/vps/v1/virtual-machines | jq
```

Renseignez les quatre valeurs dans `vps.auto.tfvars` — les trois dernières sont
obligatoires même pour un import, sans elles la ressource n'existe pas dans la
configuration et il n'y a rien à importer :

```hcl
existing_vps_id    = 123456
vps_plan           = "hostingercom-vps-kvm2-usd-1m"
vps_data_center_id = 13
vps_template_id    = 1002
```

```bash
tofu plan    # doit annoncer "1 to import" — jamais "1 to add"
tofu apply
tofu plan    # doit annoncer "No changes"
```

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

## Ce qui est géré

| Fichier | Contenu |
|---|---|
| [versions.tf](versions.tf) | Versions requises, backend (state local par défaut) |
| [providers.tf](providers.tf) | Configuration du provider Hostinger |
| [variables.tf](variables.tf) | Toutes les entrées |
| [locals.tf](locals.tf) | Valeurs dérivées |
| [main.tf](main.tf) | VPS, clés SSH, script de post-installation |
| [data.tf](data.tf) | Catalogue plans / datacenters / templates (optionnel) |
| [dns.tf](dns.tf) | Enregistrements DNS |
| [outputs.tf](outputs.tf) | IP, statut, commande SSH, catalogue |
| [scripts/post-install.sh](scripts/post-install.sh) | Durcissement de base (pare-feu, fail2ban, SSH) |

### Clés SSH

```hcl
ssh_keys = {
  "laptop" = "ssh-ed25519 AAAAC3... jonathan@laptop"
}
```

Elles sont enregistrées chez Hostinger et attachées au VPS.

### DNS

Un enregistrement sans `value` pointe automatiquement sur l'IP du VPS géré ici
(IPv4 pour un `A`, IPv6 pour un `AAAA`) :

```hcl
dns_records = {
  apex = { zone = "mondomaine.fr", name = "@", type = "A" }
  www  = { zone = "mondomaine.fr", name = "www", type = "CNAME", value = "mondomaine.fr" }
}
```

`overwrite` vaut `true` par défaut : l'enregistrement remplace ceux qui existent
déjà pour le même couple `name`/`type`. Le provider recrée tout enregistrement
modifié (`ForceNew`).

### Script de post-installation

`post_install_script_path = "scripts/post-install.sh"` enregistre le script chez
Hostinger et le rattache au VPS. Il ne s'exécute qu'à la **création ou la
réinstallation** du serveur : modifier le fichier ensuite ne reconfigure pas un
VPS déjà en place.

## Points d'attention

- **Le state contient des secrets en clair** (token API, mot de passe root).
  `.gitignore` l'exclut ; pour un usage à plusieurs, passez sur un backend
  distant chiffré (voir [versions.tf](versions.tf)).
- **`prevent_destroy = true`** protège le VPS dans [main.tf](main.tf). Pour le
  détruire ou le réinstaller volontairement, commentez cette ligne le temps d'un
  `apply`. Changer `vps_template_id` réinstalle l'OS et **efface les données**.
- **Portée du provider** : il ne couvre que le VPS, les clés SSH, les scripts de
  post-installation et le DNS. Pas de pare-feu, de snapshots ni de sauvegardes —
  cela reste à faire dans le hPanel ou sur le serveur.
- **`tofu destroy` résilie l'abonnement** du VPS.
