echo "=== Install k3s with built-in Traefik ==="
# Removed --disable traefik (INSTALL_K3S_EXEC="server" does this by default)
curl -sfL https://get.k3s.io | sh -

echo "=== Waiting for K3s service to start ==="
until systemctl is-active --quiet k3s; do
    sleep 2
done

echo "=== Prepare kubeconfig ==="
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
export KUBECONFIG=~/.kube/config

echo "=== Wait for node ==="
sudo kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml wait --for=condition=Ready node --all --timeout=300s

# helm repo add argo https://argoproj.github.io/argo-helm
# helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
# helm repo add grafana https://grafana.github.io/helm-charts
# helm repo update

# helm upgrade --install argocd argo/argo-cd \
#   -n argocd \
#   --create-namespace

# kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s

# helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
#   -n monitoring \
#   --create-namespace \
#   --set grafana.adminPassword='admin123' \
#   --set grafana.service.type=NodePort \
#   --set grafana.service.nodePort=30300 \
#   --set prometheus.service.type=NodePort \
#   --set prometheus.service.nodePort=30090


# helm upgrade --install loki grafana/loki-stack \
#   -n monitoring \
#   --create-namespace \
#   --set promtail.enabled=true \
#   --set grafana.enabled=false

# kubectl wait --namespace monitoring --for=condition=Ready pods --all --timeout=300s

# SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# cd "$SCRIPT_DIR"

# kubectl apply -f ./projects/aws-monitor-project.yaml
# kubectl apply -f ./applicationsets/aws-monitor.yaml


# nohup kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0 >/tmp/argocd-portforward.log 2>&1 </dev/null &

# nohup kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80 --address 0.0.0.0 >/tmp/grafana-portforward.log 2>&1 </dev/null &

# nohup kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090 --address 0.0.0.0 >/tmp/prometheus-portforward.log 2>&1 </dev/null &

# nohup kubectl port-forward svc/loki -n monitoring 3100:3100 --address 0.0.0.0 >/tmp/loki-portforward.log 2>&1 </dev/null &
