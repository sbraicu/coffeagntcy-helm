#!/bin/bash
set -e

echo "🚀 Deploying Lungo Chart with Dual LLM Configuration to existing cluster"

# Add Helm repositories
echo "📦 Adding Helm repositories..."
helm repo add external-secrets https://charts.external-secrets.io
helm repo add nats https://nats-io.github.io/k8s/helm/charts
helm repo add opentelemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Deploy Lungo application with dual LLM config
echo "⚡ Installing Lungo chart with dual LLM configuration..."
helm install lungo-dual-llm . --create-namespace --namespace lungo-dual-llm

echo "⏳ Waiting for services to be ready..."
sleep 60

# Wait for LoadBalancer IPs
echo "🔍 Waiting for LoadBalancer IPs..."
for i in {1..30}; do
  UI_IP=$(kubectl get svc -n lungo-dual-llm lungo-ui -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  EXCHANGE_IP=$(kubectl get svc -n lungo-dual-llm lungo-exchange -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  LOGISTICS_IP=$(kubectl get svc -n lungo-dual-llm logistic-supervisor -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  GRAFANA_IP=$(kubectl get svc -n lungo-dual-llm lungo-dual-llm-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  
  if [[ -n "$UI_IP" && -n "$EXCHANGE_IP" && -n "$LOGISTICS_IP" && -n "$GRAFANA_IP" ]]; then
    break
  fi
  echo "  Waiting for LoadBalancer IPs... ($i/30)"
  sleep 10
done

# Create LoadBalancer IP override configuration
echo "🔧 Updating UI configuration with LoadBalancer IPs..."
cat > loadbalancer-ips.yaml <<EOF
services:
  ui:
    config:
      exchangeAppApiUrl: "http://$EXCHANGE_IP:8000"
      logisticsAppApiUrl: "http://$LOGISTICS_IP:9090"
EOF

# Upgrade with LoadBalancer IPs
helm upgrade lungo-dual-llm . --namespace lungo-dual-llm -f loadbalancer-ips.yaml

echo "⏳ Waiting for UI pod to restart..."
sleep 30

# Get service endpoints
echo "🌐 Access Points:"
echo "  UI Service: http://$UI_IP:3000"
echo "  Exchange API: http://$EXCHANGE_IP:8000"
echo "  Logistics API: http://$LOGISTICS_IP:9090"
echo "  Grafana: http://$GRAFANA_IP:80 (admin/admin)"

echo ""
echo "✅ Lungo deployment with dual LLM configuration complete!"
echo ""
echo "🔧 LLM Configuration:"
echo "  Frontend services (exchange, ui) use: llm.frontend config"
echo "  Backend services (logistics, farms, mcp) use: llm.backend config"
echo ""
echo "📋 To check status:"
echo "  kubectl get pods -n lungo-dual-llm"
echo "  kubectl get svc -n lungo-dual-llm"
echo ""
echo "🧹 To cleanup:"
echo "  helm uninstall lungo-dual-llm -n lungo-dual-llm"
echo "  kind delete cluster --name lungo"
