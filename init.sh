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
  --create-namespace \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttps=30443

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

helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets-system --create-namespace


kubectl apply -f ./projects/aws-monitor-project.yaml
kubectl apply -f ./applicationsets/aws-monitor.yaml