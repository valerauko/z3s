#!/usr/bin/env bash
# Run as root on the server node after 01-os-prepare.sh.
set -euo pipefail

K0S_VERSION="v1.35.3+k0s.0"
SERVER_IP="${1:?Usage: $0 <server-ipv4> [server-ipv6]}"
SERVER_IPV6="${2:-}"

# ── Install k0s ───────────────────────────────────────────────────────────────
curl -sSfL https://get.k0s.sh | K0S_VERSION="${K0S_VERSION}" sh

# ── Write server config ───────────────────────────────────────────────────────
mkdir -p /etc/k0s
sed \
  -e "s/REPLACE_WITH_SERVER_IP/${SERVER_IP}/g" \
  -e "s/REPLACE_WITH_SERVER_IPV6/${SERVER_IPV6}/g" \
  "$(dirname "$0")/../config/k0s-server.yaml" \
  >/etc/k0s/k0s.yaml

# If no IPv6 address provided, drop the placeholder line entirely
if [[ -z "${SERVER_IPV6}" ]]; then
  sed -i '/REPLACE_WITH_SERVER_IPV6/d' /etc/k0s/k0s.yaml
fi

# ── Install and start the controller (also runs a worker on the same node) ───
k0s install controller --config /etc/k0s/k0s.yaml \
  --enable-worker \
  --cri-socket unix:///var/run/crio/crio.sock

k0s start

echo "Waiting for k0s to become ready..."
until k0s kubectl get nodes &>/dev/null; do sleep 3; done

# ── Apply CNI (Flannel) ───────────────────────────────────────────────────────
k0s kubectl apply -f "$(dirname "$0")/../manifests/flannel.yaml"

# ── Apply kube-router (network policy enforcement only) ──────────────────────
k0s kubectl apply -f "$(dirname "$0")/../manifests/kube-router-netpol.yaml"

# ── Apply local-path-provisioner ─────────────────────────────────────────────
k0s kubectl apply -f "$(dirname "$0")/../manifests/local-path-provisioner.yaml"

# ── Generate worker join token (save it — needed for 03-worker-join.sh) ──────
TOKEN_FILE="/root/k0s-worker-token"
k0s token create --role=worker >"${TOKEN_FILE}"
echo ""
echo "Worker join token saved to ${TOKEN_FILE}"
echo "Copy it to worker nodes before running 03-worker-join.sh."
echo ""
echo "Kubeconfig:"
k0s kubeconfig admin
