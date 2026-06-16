#!/bin/bash
set -e

sudo dnf install -y iptables container-selinux 2>/dev/null || sudo yum install -y iptables

curl -sfL https://get.k3s.io | sudo sh -s - --write-kubeconfig-mode 644

curl -sfL https://get.k3s.io | sh -

until systemctl is-active --quiet k3s; do
    sleep 2
done

mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
export KUBECONFIG=~/.kube/config

sudo kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml wait --for=condition=Ready node --all --timeout=300s
curl "https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4" | bash

helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install argocd argo/argo-cd \
  -n argocd \
  --create-namespace

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  --set grafana.adminPassword='admin123' \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=30300 \
  --set prometheus.service.type=NodePort \
  --set prometheus.service.nodePort=30090

helm upgrade --install loki grafana/loki-stack \
  -n monitoring \
  --create-namespace \
  --set promtail.enabled=true \
  --set grafana.enabled=false

kubectl apply -f ./projects/aws-monitor-project.yaml
kubectl apply -f ./applicationsets/aws-monitor.yaml


# Redirect external traffic
sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 -j REDIRECT --to-ports 32000

# Redirect local traffic (for testing inside the machine)
sudo iptables -t nat -A OUTPUT -p tcp --dport 8080 -j REDIRECT --to-ports 32000

#==========================================================================================================

INTERFACE="eth0"

# Fetch ClusterIPs
ARGOCD_IP=$(kubectl get svc -n argocd argocd-server -o jsonpath='{.spec.clusterIP}')
GRAFANA_IP=$(kubectl get svc -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.spec.clusterIP}')
PROMETHEUS_IP=$(kubectl get svc -n monitoring kube-prometheus-stack-prometheus -o jsonpath='{.spec.clusterIP}')
LOKI_IP=$(kubectl get svc -n monitoring loki -o jsonpath='{.spec.clusterIP}')

# Enable IP Forwarding
sysctl -w net.ipv4.ip_forward=1 > /dev/null

# Cleanup existing matching rules
iptables -t nat -D PREROUTING -i "$INTERFACE" -p tcp --dport 8080 -j DNAT --to-destination "$ARGOCD_IP:443" 2>/dev/null || true
iptables -t nat -D PREROUTING -i "$INTERFACE" -p tcp --dport 3000 -j DNAT --to-destination "$GRAFANA_IP:80" 2>/dev/null || true
iptables -t nat -D PREROUTING -i "$INTERFACE" -p tcp --dport 9090 -j DNAT --to-destination "$PROMETHEUS_IP:9090" 2>/dev/null || true
iptables -t nat -D PREROUTING -i "$INTERFACE" -p tcp --dport 3100 -j DNAT --to-destination "$LOKI_IP:3100" 2>/dev/null || true

iptables -t nat -D OUTPUT -p tcp --dport 8080 -j DNAT --to-destination "$ARGOCD_IP:443" 2>/dev/null || true
iptables -t nat -D OUTPUT -p tcp --dport 3000 -j DNAT --to-destination "$GRAFANA_IP:80" 2>/dev/null || true
iptables -t nat -D OUTPUT -p tcp --dport 9090 -j DNAT --to-destination "$PROMETHEUS_IP:9090" 2>/dev/null || true
iptables -t nat -D OUTPUT -p tcp --dport 3100 -j DNAT --to-destination "$LOKI_IP:3100" 2>/dev/null || true

# External Access (PREROUTING)
iptables -t nat -A PREROUTING -i "$INTERFACE" -p tcp --dport 8080 -j DNAT --to-destination "$ARGOCD_IP:443"
iptables -t nat -A PREROUTING -i "$INTERFACE" -p tcp --dport 3000 -j DNAT --to-destination "$GRAFANA_IP:80"
iptables -t nat -A PREROUTING -i "$INTERFACE" -p tcp --dport 9090 -j DNAT --to-destination "$PROMETHEUS_IP:9090"
iptables -t nat -A PREROUTING -i "$INTERFACE" -p tcp --dport 3100 -j DNAT --to-destination "$LOKI_IP:3100"

# Localhost Access (OUTPUT)
iptables -t nat -A OUTPUT -p tcp -o lo --dport 8080 -j DNAT --to-destination "$ARGOCD_IP:443"
iptables -t nat -A OUTPUT -p tcp -o lo --dport 3000 -j DNAT --to-destination "$GRAFANA_IP:80"
iptables -t nat -A OUTPUT -p tcp -o lo --dport 9090 -j DNAT --to-destination "$PROMETHEUS_IP:9090"
iptables -t nat -A OUTPUT -p tcp -o lo --dport 3100 -j DNAT --to-destination "$LOKI_IP:3100"

# Routing Masquerade
if ! iptables -t nat -C POSTROUTING -j MASQUERADE 2>/dev/null; then
  iptables -t nat -A POSTROUTING -j MASQUERADE
fi

# Save rules
if command -v netfilter-persistent &> /dev/null; then
  netfilter-persistent save
elif command -v iptables-save &> /dev/null; then
  [ -d "/etc/sysconfig" ] && iptables-save > /etc/sysconfig/iptables || iptables-save > /etc/iptables.rules
fi
