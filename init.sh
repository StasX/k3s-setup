#!/bin/bash
set -e

echo "=== Install k3s without Traefik ==="
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -

echo "=== Prepare kubeconfig ==="
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
export KUBECONFIG=~/.kube/config

echo "=== Wait for node ==="
kubectl wait --for=condition=Ready node --all --timeout=300s

echo "=== Install Helm ==="
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "=== Add Helm repos ==="
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

echo "=== Install ArgoCD ==="
helm upgrade --install argocd argo/argo-cd \
  -n argocd \
  --create-namespace

# Wait for ArgoCD to be fully ready
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s

echo "=== Install Prometheus + Grafana ==="
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  --set grafana.adminPassword='admin123' \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=30300 \
  --set prometheus.service.type=NodePort \
  --set prometheus.service.nodePort=30090

echo "=== Install Loki + Promtail ==="
helm upgrade --install loki grafana/loki-stack \
  -n monitoring \
  --create-namespace \
  --set promtail.enabled=true \
  --set grafana.enabled=false

echo "=== Wait for Monitoring Stack to be Ready ==="
# Crucial: Prevent port-forwarding from failing due to missing active endpoints
kubectl wait --namespace monitoring --for=condition=Ready pods --all --timeout=300s

# Get the absolute path of the git repo directory to ensure kubectl apply finds the files
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "=== Apply ArgoCD Applications ==="
kubectl apply -f ./projects/aws-monitor-project.yaml
kubectl apply -f ./applicationsets/aws-monitor.yaml

echo "=== Starting Port Forwards ==="
# Note the '</dev/null' at the end of each line. 
# This prevents the background process from holding the SSH session open.

nohup kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0 >/tmp/argocd-portforward.log 2>&1 </dev/null &

nohup kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80 --address 0.0.0.0 >/tmp/grafana-portforward.log 2>&1 </dev/null &

nohup kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090 --address 0.0.0.0 >/tmp/prometheus-portforward.log 2>&1 </dev/null &

nohup kubectl port-forward svc/loki -n monitoring 3100:3100 --address 0.0.0.0 >/tmp/loki-portforward.log 2>&1 </dev/null &

echo "=== Script Finished Successfully ==="