#!/bin/bash
set -e

echo "🚀 Deploying Lungo Multi-Cluster Architecture"

# Configuration
BACKEND_CONTEXT=${BACKEND_CONTEXT:-"kind-lungo-backend"}
FRONTEND_CONTEXT=${FRONTEND_CONTEXT:-"kind-lungo-frontend"}
BACKEND_NAMESPACE="lungo-backend"
FRONTEND_NAMESPACE="lungo-frontend"

echo "📋 Configuration:"
echo "  Backend Context: $BACKEND_CONTEXT"
echo "  Frontend Context: $FRONTEND_CONTEXT"
echo ""

# Deploy Backend Cluster
echo "🔧 Deploying Backend Cluster (AI POD1)..."
cd cluster-1-backend

echo "📦 Adding Helm repositories..."
helm repo add external-secrets https://charts.external-secrets.io
helm repo add nats https://nats-io.github.io/k8s/helm/charts
helm repo add opentelemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

echo "⚡ Installing backend services..."
helm dependency update .
helm --kube-context $BACKEND_CONTEXT install lungo-backend . \
  --create-namespace --namespace $BACKEND_NAMESPACE

echo "⏳ Waiting for backend services to be ready..."
kubectl --context $BACKEND_CONTEXT wait --namespace $BACKEND_NAMESPACE \
  --for=condition=ready pod --selector=cluster=backend --timeout=300s || true

# Get backend service endpoints
echo "🔍 Getting backend service endpoints..."
sleep 10
NATS_IP=$(kubectl --context $BACKEND_CONTEXT get svc -n $BACKEND_NAMESPACE lungo-backend-nats -o jsonpath='{.spec.clusterIP}')
OTEL_IP=$(kubectl --context $BACKEND_CONTEXT get svc -n $BACKEND_NAMESPACE lungo-backend-opentelemetry-collector -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
CLICKHOUSE_IP=$(kubectl --context $BACKEND_CONTEXT get svc -n $BACKEND_NAMESPACE lungo-backend-clickhouse -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
PAYMENTS_IP=$(kubectl --context $BACKEND_CONTEXT get svc -n $BACKEND_NAMESPACE payments-mcp -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
WEATHER_IP=$(kubectl --context $BACKEND_CONTEXT get svc -n $BACKEND_NAMESPACE weather-mcp -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
SLIM_LB_IP=$(kubectl --context $BACKEND_CONTEXT get svc -n $BACKEND_NAMESPACE lungo-backend-slim -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Wait for LoadBalancer IPs
echo "⏳ Waiting for LoadBalancer IPs..."

# First check if SLIM service is LoadBalancer type, if not patch it
SLIM_TYPE=$(kubectl --context $BACKEND_CONTEXT get svc -n $BACKEND_NAMESPACE lungo-backend-slim -o jsonpath='{.spec.type}' 2>/dev/null || echo "")
if [[ "$SLIM_TYPE" != "LoadBalancer" ]]; then
  echo "🔧 Patching SLIM service to LoadBalancer type..."
  kubectl --context $BACKEND_CONTEXT patch svc lungo-backend-slim -n $BACKEND_NAMESPACE -p '{"spec":{"type":"LoadBalancer"}}' || true
fi

for i in {1..30}; do
  OTEL_IP=$(kubectl --context $BACKEND_CONTEXT get svc -n $BACKEND_NAMESPACE lungo-backend-opentelemetry-collector -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  CLICKHOUSE_IP=$(kubectl --context $BACKEND_CONTEXT get svc -n $BACKEND_NAMESPACE lungo-backend-clickhouse -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  PAYMENTS_IP=$(kubectl --context $BACKEND_CONTEXT get svc -n $BACKEND_NAMESPACE payments-mcp -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  WEATHER_IP=$(kubectl --context $BACKEND_CONTEXT get svc -n $BACKEND_NAMESPACE weather-mcp -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  SLIM_LB_IP=$(kubectl --context $BACKEND_CONTEXT get svc -n $BACKEND_NAMESPACE lungo-backend-slim -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  
  echo "  Checking IPs ($i/30): OTEL=$OTEL_IP, CH=$CLICKHOUSE_IP, PAY=$PAYMENTS_IP, WX=$WEATHER_IP, SLIM=$SLIM_LB_IP"
  
  if [[ -n "$OTEL_IP" && -n "$CLICKHOUSE_IP" && -n "$PAYMENTS_IP" && -n "$WEATHER_IP" && -n "$SLIM_LB_IP" ]]; then
    break
  fi
  sleep 10
done

echo "📍 Backend endpoints:"
echo "  NATS: $NATS_IP:4222"
echo "  SLIM: $SLIM_LB_IP:46357 (LoadBalancer)"
echo "  OpenTelemetry: $OTEL_IP:4318"
echo "  ClickHouse: $CLICKHOUSE_IP:8123"
echo "  Payments MCP: $PAYMENTS_IP:8126"
echo "  Weather MCP: $WEATHER_IP:8125"
echo ""

# Deploy Frontend Cluster
echo "🎨 Deploying Frontend Cluster (AI POD2)..."
cd ../cluster-2-frontend

echo "📦 Adding Helm repositories..."
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

echo "🔧 Creating frontend configuration with backend endpoints..."
cat > backend-endpoints.yaml <<EOF
global:
  backendCluster:
    natsEndpoint: "nats://$NATS_IP:4222"
    slimEndpoint: "http://$SLIM_LB_IP:46357"
    otlpEndpoint: "http://$OTEL_IP:4318"

transport:
  nats:
    endpoint: "nats://$NATS_IP:4222"
    type: "NATS"
  slim:
    endpoint: "http://$SLIM_LB_IP:46357"
    type: "SLIM"

observability:
  otlpEndpoint: "http://$OTEL_IP:4318"

grafana:
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
      - name: ClickHouse
        type: grafana-clickhouse-datasource
        url: http://$CLICKHOUSE_IP:8123
        access: proxy
        basicAuth: true
        basicAuthUser: admin
        basicAuthPassword: admin
EOF

echo "⚡ Installing frontend services..."
helm dependency update .
helm --kube-context $FRONTEND_CONTEXT install lungo-frontend . \
  --create-namespace --namespace $FRONTEND_NAMESPACE \
  -f backend-endpoints.yaml

echo "⏳ Waiting for frontend services to be ready..."
kubectl --context $FRONTEND_CONTEXT wait --namespace $FRONTEND_NAMESPACE \
  --for=condition=ready pod --selector=cluster=frontend --timeout=300s || true

# Get frontend service endpoints
echo "🔍 Getting frontend service endpoints..."
sleep 10

# Wait for frontend LoadBalancer IPs
echo "⏳ Waiting for frontend LoadBalancer IPs..."
for i in {1..30}; do
  UI_IP=$(kubectl --context $FRONTEND_CONTEXT get svc -n $FRONTEND_NAMESPACE lungo-ui -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  LOGISTICS_IP=$(kubectl --context $FRONTEND_CONTEXT get svc -n $FRONTEND_NAMESPACE logistics-supervisor -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  EXCHANGE_IP=$(kubectl --context $FRONTEND_CONTEXT get svc -n $FRONTEND_NAMESPACE lungo-exchange -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  GRAFANA_IP=$(kubectl --context $FRONTEND_CONTEXT get svc -n $FRONTEND_NAMESPACE lungo-frontend-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  
  if [[ -n "$UI_IP" && -n "$LOGISTICS_IP" && -n "$EXCHANGE_IP" && -n "$GRAFANA_IP" ]]; then
    break
  fi
  echo "  Waiting for frontend LoadBalancer IPs... ($i/30)"
  sleep 10
done

# Update UI configuration with LoadBalancer IPs
echo "🔧 Updating UI configuration with LoadBalancer IPs..."
cat > frontend-lb-config.yaml <<EOF
services:
  ui:
    config:
      exchangeAppApiUrl: "http://$EXCHANGE_IP:8000"
      logisticsAppApiUrl: "http://$LOGISTICS_IP:9090"
EOF

# Upgrade frontend with LoadBalancer IPs
helm --kube-context $FRONTEND_CONTEXT upgrade lungo-frontend . \
  --namespace $FRONTEND_NAMESPACE \
  -f backend-endpoints.yaml \
  -f frontend-lb-config.yaml

echo ""
echo "✅ Multi-cluster deployment complete!"
echo ""
echo "🌐 Access Points:"
echo "  Lungo UI: http://$UI_IP:3000"
echo "  Exchange API: http://$EXCHANGE_IP:8000"
echo "  Logistics API: http://$LOGISTICS_IP:9090"
echo "  Grafana: http://$GRAFANA_IP:3000 (admin/admin)"
echo ""
echo "🔧 Backend Services:"
echo "  Weather MCP: Available via backend cluster"
echo "  Payment MCP: Available via backend cluster"
echo "  Farm Agents: Running in backend cluster"
echo ""
echo "📊 Architecture:"
echo "  Backend Cluster: Infrastructure + Farm Services"
echo "  Frontend Cluster: UI + Logistics Supervisor + Monitoring"
