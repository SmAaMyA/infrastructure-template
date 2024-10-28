#!/bin/bash

echo "Starting full production setup for Monitoring Server on Ubuntu 24..."

# 1. System Hardening
echo "Applying system hardening..."
apt update && apt upgrade -y && apt install -y unattended-upgrades
dpkg-reconfigure --priority=low unattended-upgrades

# Configure UFW firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 9090 # Prometheus
ufw allow 3000 # Grafana
ufw allow 9200 # Elasticsearch (if needed)
ufw enable

# SSH Hardening: disable root login, enforce key-based authentication
sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# Enable AppArmor for enhanced security
systemctl enable apparmor
systemctl start apparmor

# 2. Essential Package Installation
echo "Installing essential packages..."
apt install -y curl vim ufw net-tools gnupg sudo auditd fail2ban logrotate

# Enable and start Fail2Ban
systemctl enable fail2ban
systemctl start fail2ban

# 3. Install Prometheus and Configure Alerts
kubectl apply -f https://prometheus-community.github.io/helm-charts
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml

# Prometheus alerts configuration for critical monitoring
cat <<EOF >/etc/prometheus/alert.rules.yml
groups:
  - name: node-health
    rules:
      - alert: DiskRunningOut
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.15
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "Node running out of disk space"
      - alert: HighNetworkTraffic
        expr: rate(node_network_receive_bytes_total[5m]) > 1e6
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High network traffic detected on node"
EOF
systemctl restart prometheus

# 4. Install Grafana and Configure for Monitoring
kubectl apply -f https://raw.githubusercontent.com/grafana/grafana/main/production/grafana.yaml
kubectl apply -f https://grafana.github.io/loki/charts/loki-stack

# 5. Secure Elastic Stack (optional) and Log Rotation
echo "Configuring SSL/TLS for Elasticsearch..."
openssl req -newkey rsa:4096 -nodes -keyout /etc/elasticsearch/ssl/elasticsearch.key -out /etc/elasticsearch/ssl/elasticsearch.crt -subj "/CN=elasticsearch"
kubectl create secret generic elastic-cert --from-file=/etc/elasticsearch/ssl/elasticsearch.crt --from-file=/etc/elasticsearch/ssl/elasticsearch.key -n monitoring

# Enable log rotation for system and application logs
echo "/var/log/*.log {
  daily
  missingok
  rotate 7
  compress
  delaycompress
  notifempty
  create 640 root adm
}" >/etc/logrotate.d/all-logs

echo "Monitoring server setup complete with production-grade hardening and configuration."
