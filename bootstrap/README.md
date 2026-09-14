# Amorçage — bucket R2 pour l'état distant

Ce module crée le bucket Cloudflare R2 qui héberge l'état OpenTofu de la
configuration racine.

## Pourquoi un module séparé

Un bucket qui héberge un état ne peut pas être décrit dans cet état : le
détruire rendrait l'état illisible, et le recréer exigerait un état qui n'existe
plus. C'est l'amorçage (*bootstrap*) classique de toute infrastructure à état
distant.

Le compromis retenu : **le code est versionné, l'état de ce module ne l'est
pas**. La reproductibilité depuis Git est donc préservée — ce module se rejoue
tel quel sur un compte neuf — et son état local reste jetable, puisque le bucket
se réimporte en une commande.

## Utilisation

Une seule fois, avant tout `tofu init` à la racine.

```bash
export CLOUDFLARE_API_TOKEN="..."   # permission : Workers R2 Storage — Write
export TF_VAR_cloudflare_account_id="..."

cd bootstrap
tofu init
tofu apply
```

Puis reportez le bloc affiché par l'output dans `../versions.tf` :

```bash
tofu output -raw backend_block
```

## Activer le versioning du bucket

Le cahier des charges demande un bucket versionné, pour récupérer un état
corrompu. Le provider Cloudflare n'expose pas ce réglage : il s'active dans le
tableau de bord R2 (*Settings → Object versioning*), ou via l'API S3 :

```bash
aws s3api put-bucket-versioning \
  --bucket jbessa-tfstate \
  --versioning-configuration Status=Enabled \
  --endpoint-url "https://<account_id>.r2.cloudflarestorage.com"
```

À faire **avant** de migrer l'état : le versioning ne s'applique pas
rétroactivement aux objets déjà écrits.

## Identifiants du backend

Le backend S3 n'utilise pas le token Cloudflare mais des identifiants R2
dédiés, à générer dans *R2 → Manage API tokens* :

```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
```

## Reconstruire cet état s'il est perdu

Le bucket existe toujours, seul l'état local a disparu :

```bash
tofu import cloudflare_r2_bucket.state '<account_id>/jbessa-tfstate/default'
```
