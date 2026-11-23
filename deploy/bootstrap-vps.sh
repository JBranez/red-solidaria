#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${1:?Uso: bootstrap-vps.sh <repo-publico-https> <app-dir>}"
APP_DIR="${2:-/opt/red-solidaria}"
DEPLOY_USER="${SUDO_USER:-$USER}"

if [[ "$EUID" -ne 0 ]]; then
  echo "ERROR: ejecuta este script mediante sudo." >&2
  exit 1
fi
if [[ -z "$DEPLOY_USER" || "$DEPLOY_USER" == "root" ]]; then
  echo "ERROR: usa una cuenta normal con sudo para el despliegue (por ejemplo ubuntu)." >&2
  exit 1
fi
if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "ERROR: SQL Server Linux container requiere un host x86_64/amd64 para este despliegue." >&2
  exit 1
fi
if [[ ! -r /etc/os-release ]] || ! grep -qi 'ubuntu' /etc/os-release; then
  echo "ERROR: este instalador está preparado para Ubuntu 24.04/22.04." >&2
  exit 1
fi

MEM_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
DISK_KB="$(df -Pk / | awk 'NR==2 {print $4}')"
if [[ "$MEM_KB" -lt 2097152 ]]; then
  echo "ERROR: SQL Server Linux container requiere al menos 2 GiB de RAM." >&2
  exit 1
fi
if [[ "$MEM_KB" -lt 4194304 ]]; then
  echo "ADVERTENCIA: menos de 4 GiB RAM; para API + Angular + SQL Server se recomiendan 4 GiB o más." >&2
fi
if [[ "$DISK_KB" -lt 20971520 ]]; then
  echo "ERROR: quedan menos de 20 GiB libres; se recomiendan al menos 20 GiB." >&2
  exit 1
fi

sudo apt-get update
sudo apt-get install -y ca-certificates curl openssl git ufw
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker

# Swap de contingencia para compilaciones Node/Angular en una EC2 de 4 GiB.
# SQL Server mantiene su propio limite de memoria y no debe depender del swap.
if ! sudo swapon --show=NAME --noheadings | grep -qx '/swapfile'; then
  if [[ ! -f /swapfile ]]; then
    sudo fallocate -l 2G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
  fi
  sudo swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

# No se abre 1433 al público; Docker solo lo publica en 127.0.0.1.
SSH_PORT="${SSH_PORT:-22}"
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow "${SSH_PORT}/tcp"
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

sudo mkdir -p "${APP_DIR}"
sudo chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${APP_DIR}"
if [[ ! -d "${APP_DIR}/.git" ]]; then
  git clone "${REPO_URL}" "${APP_DIR}"
else
  git -C "${APP_DIR}" remote set-url origin "${REPO_URL}"
fi

# Docker group otorga privilegios equivalentes a root: úselo solo con esta cuenta de despliegue.
sudo usermod -aG docker "${DEPLOY_USER}"

# Certificado privado para TLS entre el backend y SQL Server dentro de la red Docker.
CERT_DIR="${APP_DIR}/deploy/certs"
SECRET_DIR="${APP_DIR}/.secrets"
sudo mkdir -p "${CERT_DIR}" "${SECRET_DIR}"
sudo chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${CERT_DIR}" "${SECRET_DIR}"
if [[ ! -s "${CERT_DIR}/ca.crt" || ! -s "${CERT_DIR}/server-fullchain.pem" || ! -s "${CERT_DIR}/server.key" ]]; then
  openssl genrsa -out "${SECRET_DIR}/ca.key" 4096
  openssl req -x509 -new -nodes -key "${SECRET_DIR}/ca.key" -sha256 -days 3650 \
    -out "${CERT_DIR}/ca.crt" -subj "/CN=RedSolidaria Internal SQL CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign,digitalSignature"
  openssl genrsa -out "${CERT_DIR}/server.key" 2048
  openssl req -new -key "${CERT_DIR}/server.key" -out "${SECRET_DIR}/server.csr" -subj "/CN=sqlserver" \
    -addext "subjectAltName=DNS:sqlserver"
  cat > "${SECRET_DIR}/server.ext" <<'EOF'
subjectAltName=DNS:sqlserver
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EOF
  openssl x509 -req -in "${SECRET_DIR}/server.csr" -CA "${CERT_DIR}/ca.crt" -CAkey "${SECRET_DIR}/ca.key" \
    -CAcreateserial -out "${SECRET_DIR}/server.crt" -days 825 -sha256 -extfile "${SECRET_DIR}/server.ext"
  cat "${SECRET_DIR}/server.crt" "${CERT_DIR}/ca.crt" > "${CERT_DIR}/server-fullchain.pem"
  sudo chown root:root "${CERT_DIR}/ca.crt" "${CERT_DIR}/server-fullchain.pem"
  sudo chown 10001:0 "${CERT_DIR}/server.key"
  sudo chmod 444 "${CERT_DIR}/ca.crt" "${CERT_DIR}/server-fullchain.pem"
  sudo chmod 440 "${CERT_DIR}/server.key"
  sudo chmod 700 "${SECRET_DIR}/ca.key"
  sudo chown root:root "${SECRET_DIR}/ca.key"
fi

sudo chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${APP_DIR}"
sudo chown root:root "${CERT_DIR}/ca.crt" "${CERT_DIR}/server-fullchain.pem"
sudo chown 10001:0 "${CERT_DIR}/server.key"
sudo chmod 444 "${CERT_DIR}/ca.crt" "${CERT_DIR}/server-fullchain.pem"
sudo chmod 440 "${CERT_DIR}/server.key"
sudo chown root:root "${SECRET_DIR}" "${SECRET_DIR}/ca.key"
sudo chmod 700 "${SECRET_DIR}"
sudo chmod 600 "${SECRET_DIR}/ca.key"

sudo -u "${DEPLOY_USER}" git -C "${APP_DIR}" fetch origin
sudo -u "${DEPLOY_USER}" git -C "${APP_DIR}" checkout main
sudo -u "${DEPLOY_USER}" git -C "${APP_DIR}" pull --ff-only origin main
sudo docker run --rm hello-world
sudo docker compose version

echo "Bootstrap completado. Vuelve a conectar por SSH para aplicar el nuevo grupo docker."
