#!/usr/bin/env bash
# Post-installation VPS Hostinger (Debian / Ubuntu).
# Exécuté par Hostinger en root, une seule fois, après l'installation de l'OS.
# Il n'est PAS rejoué par `tofu apply` : modifier ce fichier ne reconfigure pas
# un VPS déjà provisionné (il faut le réinstaller, ou appliquer les changements
# à la main / via un outil de configuration).
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "[post-install] Mise à jour du système"
apt-get update -qq
apt-get upgrade -y -qq

echo "[post-install] Paquets de base"
apt-get install -y -qq \
  ca-certificates curl gnupg \
  ufw fail2ban unattended-upgrades \
  htop vim git

echo "[post-install] Pare-feu (SSH, HTTP, HTTPS)"
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "[post-install] Durcissement SSH"
# On ne coupe l'authentification par mot de passe que si une clé publique est
# déjà en place — sinon on se verrouillerait dehors.
if [ -s /root/.ssh/authorized_keys ]; then
  cat >/etc/ssh/sshd_config.d/99-hardening.conf <<'EOF'
PasswordAuthentication no
PermitRootLogin prohibit-password
KbdInteractiveAuthentication no
EOF
  systemctl reload ssh || systemctl reload sshd
  echo "[post-install] Authentification par mot de passe désactivée"
else
  echo "[post-install] AVERTISSEMENT : aucune clé SSH trouvée dans /root/.ssh/authorized_keys," \
    "l'authentification par mot de passe reste active."
fi

echo "[post-install] Mises à jour de sécurité automatiques"
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "[post-install] fail2ban"
systemctl enable --now fail2ban

echo "[post-install] Terminé"
