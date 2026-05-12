#!/usr/bin/env bash
# Run as root on each worker node after 01-os-prepare.sh.
# Usage: ./03-worker-join.sh <server-ip> <join-token>
#   or:  ./03-worker-join.sh <server-ip> /path/to/token-file
set -euo pipefail

K0S_VERSION="v1.35.3+k0s.0"  # Must match server version
SERVER_IP="${1:?Usage: $0 <server-ip> <token-or-token-file>}"
TOKEN_ARG="${2:?Usage: $0 <server-ip> <token-or-token-file>}"

if [[ -f "${TOKEN_ARG}" ]]; then
  TOKEN="$(cat "${TOKEN_ARG}")"
else
  TOKEN="${TOKEN_ARG}"
fi

# ── Install k0s ───────────────────────────────────────────────────────────────
curl -sSfL https://get.k0s.sh | K0S_VERSION="${K0S_VERSION}" sh

# ── Write worker config ───────────────────────────────────────────────────────
mkdir -p /etc/k0s
cat >/etc/k0s/k0s-worker.yaml <<EOF
apiVersion: k0s.k0sproject.io/v1beta1
kind: WorkerConfig
metadata:
  name: default
spec:
  apiServer: "https://${SERVER_IP}:6443"
  containerRuntimeEndpoint: unix:///var/run/crio/crio.sock
  kubelet:
    maxPods: 50
    kubeAPIQPS: 5
    kubeAPIBurst: 10
    serializeImagePulls: true
    evictionHard:
      memory.available: "100Mi"
    systemReserved:
      memory: "200Mi"
EOF

# ── Install and start the worker ─────────────────────────────────────────────
echo "${TOKEN}" | k0s install worker \
  --config /etc/k0s/k0s-worker.yaml \
  --cri-socket unix:///var/run/crio/crio.sock \
  --token-file /dev/stdin

k0s start

echo "Worker joined. Check status on the server with: k0s kubectl get nodes"
