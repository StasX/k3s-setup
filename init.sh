#!/bin/bash
set -e

echo "=== Update system ==="
sudo dnf update -y || sudo yum update -y

echo "=== Install basic tools ==="
sudo dnf install -y curl wget git tar gzip || sudo yum install -y curl wget git tar gzip

echo "=== Install k3s without Traefik ==="
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik" sh -

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
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

echo "=== Install ingress-nginx ==="
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443

echo "=== Install ArgoCD ==="
helm upgrade --install argocd argo/argo-cd \
  -n argocd \
  --create-namespace

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






nohup kubectl port-forward svc/argocd-server \
  -n argocd \
  8080:443 \
  --address 0.0.0.0 \
  >/tmp/argocd-portforward.log 2>&1 &

nohup kubectl port-forward svc/kube-prometheus-stack-grafana \
  -n monitoring \
  3000:80 \
  --address 0.0.0.0 \
  >/tmp/grafana-portforward.log 2>&1 &

nohup kubectl port-forward svc/kube-prometheus-stack-prometheus \
  -n monitoring \
  9090:9090 \
  --address 0.0.0.0 \
  >/tmp/prometheus-portforward.log 2>&1 &

nohup kubectl port-forward svc/loki \
  -n monitoring \
  3100:3100 \
  --address 0.0.0.0 \
  >/tmp/loki-portforward.log 2>&1 &

kubectl apply -f ./projects/aws-monitor-project.yaml
kubectl apply -f ./applicationsets/aws-monitor.yaml