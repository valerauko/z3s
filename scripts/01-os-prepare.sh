#!/usr/bin/env bash
# Run as root on every node (server and workers) before k0s setup.
set -euo pipefail

CRIO_VERSION="1.35"  # Match your target Kubernetes version

# ── Journald ────────────────────────────────────────────────────────────────
cp /dev/stdin /etc/systemd/journald.conf <<'EOF'
[Journal]
SystemMaxUse=16M
RuntimeMaxUse=16M
Compress=yes
Storage=persistent
MaxLevelStore=warning
EOF
systemctl restart systemd-journald

# ── Kernel modules required by Kubernetes networking ─────────────────────────
cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# ── Sysctl ───────────────────────────────────────────────────────────────────
cat >/etc/sysctl.d/99-k8s.conf <<'EOF'
vm.swappiness=10
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
EOF
sysctl --system

# ── zram swap ────────────────────────────────────────────────────────────────
# Uses ~50% of RAM as compressed swap. On 1GB nodes this gives ~500MB extra
# effective memory at a ~2:1 compression ratio, with no disk I/O.
apt-get install -y zram-tools

cat >/etc/default/zramswap <<'EOF'
ALGO=lz4
PERCENT=50
EOF

systemctl enable --now zramswap

# ── Disable existing swap (disk-backed swap causes I/O storms on low-RAM nodes)
swapoff -a
# Remove any swap entries from fstab
sed -i '/\bswap\b/d' /etc/fstab

# ── cri-o ────────────────────────────────────────────────────────────────────
apt-get install -y software-properties-common curl gpg

# Add cri-o apt repo
curl -fsSL "https://pkgs.k8s.io/addons:/cri-o:/stable:/v${CRIO_VERSION}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] \
https://pkgs.k8s.io/addons:/cri-o:/stable:/v${CRIO_VERSION}/deb/ /" \
  >/etc/apt/sources.list.d/cri-o.list

apt-get update
apt-get install -y cri-o

# ── crun ─────────────────────────────────────────────────────────────────────
apt-get install -y crun

# Tell cri-o to use crun instead of runc
cat >/etc/crio/crio.conf.d/10-crun.conf <<'EOF'
[crio.runtime]
default_runtime = "crun"

[crio.runtime.runtimes.crun]
runtime_path = "/usr/bin/crun"
runtime_type = "oci"
runtime_root = "/run/crun"
EOF

systemctl enable --now crio

echo "OS preparation complete. Reboot recommended before proceeding."
