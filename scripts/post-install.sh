#!/usr/bin/env bash
#
# Bootstrap du nœud — VPS Hostinger, Debian, cluster K3s mono-nœud.
#
# Exécuté par Hostinger en root, une seule fois, à l'installation de l'OS.
# Il n'est PAS rejoué par `tofu apply` : pour le rejouer, il faut réinstaller
# le serveur (changer vps_template_id, qui est un update in-place).
#
# CONTRAINTE — ce script est stocké chez l'hébergeur et consultable depuis son
# interface. Il ne doit contenir AUCUN secret : ni clé age, ni jeton Teleport,
# ni identifiants R2. Tout le reste entre par ArgoCD.
#
# Périmètre volontairement limité : utilisateur non privilégié, nftables,
# mises à jour de sécurité, K3s. Rien d'autre.
set -euo pipefail

# --- Configuration -----------------------------------------------------------

ADMIN_USER="ops"

# renovate: datasource=github-releases depName=k3s-io/k3s
K3S_VERSION="v1.36.4+k3s1"

# Réservations kubelet : ~900 Mo pour le système et le plan de contrôle.
SYSTEM_RESERVED="cpu=200m,memory=600Mi"
KUBE_RESERVED="cpu=100m,memory=300Mi"
EVICTION_HARD="memory.available<250Mi"

# CIDR par défaut de K3s, autorisés en entrée pour le trafic interne au cluster.
POD_CIDR="10.42.0.0/16"
SERVICE_CIDR="10.43.0.0/16"

LOG=/var/log/post-install.log
exec > >(tee -a "$LOG") 2>&1
trap 'echo "[post-install] ÉCHEC ligne $LINENO — voir $LOG"' ERR

echo "[post-install] Démarrage : $(date --iso-8601=seconds)"
export DEBIAN_FRONTEND=noninteractive

# --- Système -----------------------------------------------------------------

echo "[post-install] Mise à jour et paquets de base"
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  ca-certificates curl gnupg nftables unattended-upgrades jq

# kubelet refuse de démarrer avec le swap actif dans sa configuration par défaut.
echo "[post-install] Désactivation du swap"
swapoff -a || true
sed -i.bak '/[[:space:]]swap[[:space:]]/s/^/#/' /etc/fstab

echo "[post-install] Paramètres noyau pour Kubernetes"
cat >/etc/sysctl.d/99-k3s.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl --quiet --system

# --- Utilisateur non privilégié ----------------------------------------------

echo "[post-install] Création de l'utilisateur $ADMIN_USER"
if ! id -u "$ADMIN_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --groups sudo "$ADMIN_USER"
  passwd --lock "$ADMIN_USER"
fi

# Les clés publiques attachées au VPS par Terraform atterrissent chez root.
# Une clé publique n'est pas un secret : la recopier ici ne viole pas le
# contrat énoncé en tête de fichier.
if [ -s /root/.ssh/authorized_keys ]; then
  install -d -m 700 -o "$ADMIN_USER" -g "$ADMIN_USER" "/home/$ADMIN_USER/.ssh"
  install -m 600 -o "$ADMIN_USER" -g "$ADMIN_USER" \
    /root/.ssh/authorized_keys "/home/$ADMIN_USER/.ssh/authorized_keys"
  echo "[post-install] Clés SSH recopiées vers $ADMIN_USER"
else
  echo "[post-install] AVERTISSEMENT : aucune clé SSH sur le compte root."
fi

echo "%sudo ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/90-sudo-nopasswd
chmod 440 /etc/sudoers.d/90-sudo-nopasswd

# --- SSH ---------------------------------------------------------------------

# Le port 22 reste ouvert ici : Teleport n'est pas encore déployé. Il sera
# fermé définitivement à l'étape suivante du plan de construction, une fois
# l'accès administratif bascule sur Teleport.
#
# 00- et non 99- : sshd applique la PREMIÈRE occurrence de chaque directive
# rencontrée dans l'ordre alphabétique des fichiers inclus (l'inverse de la
# plupart des systèmes de config). L'image Hostinger dépose déjà
# /etc/ssh/sshd_config.d/50-cloud-init.conf avec `PasswordAuthentication yes` :
# un fichier 99- serait lu après et donc ignoré pour cette directive.
# Constaté en usage réel — PermitRootLogin no fonctionnait (non touché par
# 50-cloud-init.conf), PasswordAuthentication no était silencieusement perdu.
if [ -s "/home/$ADMIN_USER/.ssh/authorized_keys" ]; then
  cat >/etc/ssh/sshd_config.d/00-hardening.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
  systemctl reload ssh 2>/dev/null || systemctl reload sshd
  echo "[post-install] SSH durci : clé obligatoire, root refusé"
else
  echo "[post-install] AVERTISSEMENT : SSH laissé en l'état, aucune clé déployée."
fi

# --- Pare-feu ----------------------------------------------------------------

echo "[post-install] nftables en refus par défaut"

# Les plages Cloudflare changent : un script et un timer les rafraîchissent
# plutôt que de les figer ici.
cat >/usr/local/sbin/refresh-cloudflare-ips <<'EOF'
#!/usr/bin/env bash
# Recharge les plages Cloudflare dans les sets nftables.
set -euo pipefail
v4=$(curl -fsS --max-time 20 https://www.cloudflare.com/ips-v4)
v6=$(curl -fsS --max-time 20 https://www.cloudflare.com/ips-v6)
[ -n "$v4" ] && [ -n "$v6" ] || { echo "plages vides, abandon"; exit 1; }

nft flush set inet filter cloudflare_v4
nft flush set inet filter cloudflare_v6
nft add element inet filter cloudflare_v4 "{ $(echo "$v4" | paste -sd,) }"
nft add element inet filter cloudflare_v6 "{ $(echo "$v6" | paste -sd,) }"
echo "Plages Cloudflare rechargées : $(echo "$v4" | wc -l) v4, $(echo "$v6" | wc -l) v6"
EOF
chmod 755 /usr/local/sbin/refresh-cloudflare-ips

cat >/etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
# Généré par le script de post-installation. Source de vérité du pare-feu.
flush ruleset

table inet filter {
  set cloudflare_v4 {
    type ipv4_addr
    flags interval
  }

  set cloudflare_v6 {
    type ipv6_addr
    flags interval
  }

  chain input {
    type filter hook input priority filter; policy drop;

    ct state established,related accept
    ct state invalid drop
    iif lo accept

    # Trafic interne au cluster : pods, services et interfaces CNI.
    iifname { "cni0", "flannel.1" } accept
    ip saddr $POD_CIDR accept
    ip saddr $SERVICE_CIDR accept

    icmp type echo-request limit rate 5/second accept
    icmpv6 type { echo-request, nd-neighbor-solicit, nd-neighbor-advert, nd-router-advert } accept

    # SSH : temporaire, à retirer dès que Teleport prend le relais.
    tcp dport 22 accept

    # HTTP(S) uniquement depuis le proxy Cloudflare : l'origine ne peut pas
    # être jointe en direct.
    tcp dport { 80, 443 } ip saddr @cloudflare_v4 accept
    tcp dport { 80, 443 } ip6 saddr @cloudflare_v6 accept
  }

  chain forward {
    # K3s pose ses propres règles de forward pour le réseau des pods.
    type filter hook forward priority filter; policy accept;
  }

  chain output {
    type filter hook output priority filter; policy accept;
  }
}
EOF

systemctl enable nftables
systemctl restart nftables
/usr/local/sbin/refresh-cloudflare-ips

cat >/etc/systemd/system/refresh-cloudflare-ips.service <<'EOF'
[Unit]
Description=Recharge les plages Cloudflare dans nftables
After=network-online.target nftables.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/refresh-cloudflare-ips
EOF

cat >/etc/systemd/system/refresh-cloudflare-ips.timer <<'EOF'
[Unit]
Description=Rafraîchissement quotidien des plages Cloudflare

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now refresh-cloudflare-ips.timer

# --- Mises à jour de sécurité ------------------------------------------------

echo "[post-install] Mises à jour de sécurité automatiques"
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable --now unattended-upgrades

# --- K3s ---------------------------------------------------------------------

echo "[post-install] Installation de K3s $K3S_VERSION"
install -d -m 755 /etc/rancher/k3s

cat >/etc/rancher/k3s/config.yaml <<EOF
# Traefik est déployé par ArgoCD, pas par K3s : sa configuration doit vivre
# dans le dépôt GitOps.
disable:
  - traefik

# Chiffrement des Secrets au repos.
secrets-encryption: true

write-kubeconfig-mode: "0600"

kubelet-arg:
  - "system-reserved=$SYSTEM_RESERVED"
  - "kube-reserved=$KUBE_RESERVED"
  - "eviction-hard=$EVICTION_HARD"
EOF

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" sh -

echo "[post-install] Attente du nœud"
for _ in $(seq 1 60); do
  if k3s kubectl get node >/dev/null 2>&1; then break; fi
  sleep 5
done
k3s kubectl get node || echo "[post-install] AVERTISSEMENT : nœud pas encore prêt"

# kubectl utilisable par l'utilisateur non privilégié.
install -d -m 700 -o "$ADMIN_USER" -g "$ADMIN_USER" "/home/$ADMIN_USER/.kube"
install -m 600 -o "$ADMIN_USER" -g "$ADMIN_USER" \
  /etc/rancher/k3s/k3s.yaml "/home/$ADMIN_USER/.kube/config"

echo "[post-install] Terminé : $(date --iso-8601=seconds)"
echo "[post-install] Reste à faire : Teleport, puis fermeture du port 22."
