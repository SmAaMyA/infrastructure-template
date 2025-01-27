#!/bin/bash

echo "Starting foundational setup for a clean VM state..."

# 1. System Updates and Essential Tools
apt update && apt upgrade -y
apt install -y curl wget gnupg lsb-release software-properties-common

# 2. Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
apt update && apt install -y docker-ce docker-ce-cli containerd.io
systemctl enable docker && systemctl start docker

# 3. Install Kubernetes Tools
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
apt update && apt install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet && systemctl start kubelet

# 4. Basic Firewall Configuration
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh

echo "Foundational setup complete."

# Configuration Variables
CONTROL_PLANE_IP="192.168.1.100"
POD_NETWORK_CIDR="10.244.0.0/16"

echo "Starting refined setup for Kubernetes Control Plane..."

# System Hardening and Updates
apt update && apt upgrade -y && apt install -y unattended-upgrades
dpkg-reconfigure --priority=low unattended-upgrades
ufw default deny incoming
ufw allow ssh
ufw allow 6443/tcp # Kubernetes API server
ufw enable

# Kubernetes Control Plane Setup
kubeadm init --apiserver-advertise-address=${CONTROL_PLANE_IP} --pod-network-cidr=${POD_NETWORK_CIDR} | tee kubeadm-init.log

export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

# Etcd Backup Verification
BACKUP_DIR=/backups
LATEST_BACKUP=$(ls -t $BACKUP_DIR/etcd-* | head -1)
etcdctl snapshot restore "$LATEST_BACKUP" --data-dir=/tmp/etcd-restore-test

echo "Kubernetes Control Plane refined setup complete."

# Install Prometheus Node Exporter for resource monitoring
echo "Installing Prometheus Node Exporter..."
wget https://github.com/prometheus/node_exporter/releases/download/v1.3.1/node_exporter-1.3.1.linux-amd64.tar.gz
tar xvfz node_exporter-1.3.1.linux-amd64.tar.gz
mv node_exporter-1.3.1.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-1.3.1.linux-amd64*

# Start Node Exporter as a systemd service
cat <<EOF >/etc/systemd/system/node_exporter.service
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=default.target
EOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter
echo "Node Exporter installed and started."

# Install Promtail for log collection
echo "Installing Promtail for centralized log collection..."
wget https://github.com/grafana/loki/releases/download/v2.3.0/promtail-linux-amd64.zip
unzip promtail-linux-amd64.zip
mv promtail-linux-amd64 /usr/local/bin/promtail
rm promtail-linux-amd64.zip

# Configure Promtail with default configuration for this node
cat <<EOF >/etc/promtail-local-config.yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/log/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          __path__: /var/log/*log
EOF

# Start Promtail as a systemd service
cat <<EOF >/etc/systemd/system/promtail.service
[Unit]
Description=Promtail service
After=network.target

[Service]
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail-local-config.yaml

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable promtail
systemctl start promtail
echo "Promtail installed and started."
