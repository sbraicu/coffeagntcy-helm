#!/bin/bash
set -e

echo "🚀 Deploying Lungo on OpenShift Cluster"
echo "=================================================="

# Configuration
NAMESPACE="lungo"
RELEASE_NAME="lungo"
METALLB_VERSION="v0.14.8"
IP_POOL_START="10.100.100.200"
IP_POOL_END="10.100.100.220"

# Check prerequisites
echo "📋 Checking prerequisites..."
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl."
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo "❌ helm not found. Please install Helm 3.x."
    exit 1
fi

if [ -z "$KUBECONFIG" ]; then
    echo "⚠️  KUBECONFIG not set. Using default kubeconfig."
fi

# Test cluster connectivity
echo "🔗 Testing cluster connectivity..."
kubectl cluster-info > /dev/null || {
    echo "❌ Cannot connect to cluster. Check your kubeconfig."
    exit 1
}

echo "✅ Prerequisites check passed"

# Step 1: Install MetalLB with OpenShift SCCs
echo ""
echo "🔧 Step 1: Installing MetalLB LoadBalancer..."

# Create MetalLB SCCs
echo "  Creating MetalLB Security Context Constraints..."
kubectl apply -f configs/metallb-scc.yaml

# Install MetalLB
echo "  Installing MetalLB components..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml

# Wait for MetalLB to be ready
echo "  Waiting for MetalLB to be ready..."
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=120s

# Configure MetalLB IP pool
echo "  Configuring MetalLB IP pool..."
kubectl apply -f configs/metallb-config.yaml

echo "✅ MetalLB installation completed"

# Step 2: Setup Storage
echo ""
echo "💾 Step 2: Setting up storage..."

# Create local storage class and PV
kubectl apply -f configs/local-storage.yaml

# Create directory on worker node
echo "  Creating storage directory on worker node..."
WORKER_NODE=$(kubectl get nodes --selector='!node-role.kubernetes.io/master' -o jsonpath='{.items[0].metadata.name}')
kubectl debug node/${WORKER_NODE} -it --image=busybox -- mkdir -p /host/tmp/clickhouse-data || true

echo "✅ Storage setup completed"

# Step 3: Setup Security Context Constraints
echo ""
echo "🔒 Step 3: Setting up Security Context Constraints..."

# Add anyuid SCC to default service account
oc adm policy add-scc-to-user anyuid -z default -n ${NAMESPACE} || kubectl create namespace ${NAMESPACE}
oc adm policy add-scc-to-user anyuid -z default -n ${NAMESPACE}

# Add anyuid SCC to Grafana service account
oc adm policy add-scc-to-user anyuid -z lungo-grafana -n ${NAMESPACE} 2>/dev/null || echo "  Grafana SCC will be added after deployment"

echo "✅ Security setup completed"

# Step 4: Deploy Application
echo ""
echo "⚡ Step 4: Deploying Lungo application..."

# Add Helm repositories
echo "  Adding Helm repositories..."
helm repo add external-secrets https://charts.external-secrets.io
helm repo add nats https://nats-io.github.io/k8s/helm/charts
helm repo add opentelemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Update dependencies
echo "  Updating Helm dependencies..."
cd helm
helm dependency update
cd ..

# Install application
echo "  Installing Lungo application..."
helm install ${RELEASE_NAME} ./helm \
    --create-namespace \
    --namespace ${NAMESPACE}

echo "✅ Application deployment initiated"

# Step 5: Wait for services and configure LoadBalancer IPs
echo ""
echo "⏳ Step 5: Waiting for services to be ready..."

# Wait for core infrastructure
echo "  Waiting for ClickHouse to be ready..."
kubectl wait --for=condition=ready pod lungo-clickhouse-shard0-0 -n ${NAMESPACE} --timeout=300s

echo "  Waiting for application pods..."
sleep 60

# Wait for LoadBalancer IPs
echo "  Waiting for LoadBalancer IP assignment..."
for i in {1..30}; do
    UI_IP=$(kubectl get svc -n ${NAMESPACE} lungo-ui -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    EXCHANGE_IP=$(kubectl get svc -n ${NAMESPACE} lungo-exchange -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    LOGISTICS_IP=$(kubectl get svc -n ${NAMESPACE} logistic-supervisor -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    GRAFANA_IP=$(kubectl get svc -n ${NAMESPACE} lungo-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [[ -n "$UI_IP" && -n "$EXCHANGE_IP" && -n "$LOGISTICS_IP" && -n "$GRAFANA_IP" ]]; then
        break
    fi
    echo "    Waiting for LoadBalancer IPs... ($i/30)"
    sleep 10
done

# Update UI configuration with LoadBalancer IPs
if [[ -n "$UI_IP" && -n "$EXCHANGE_IP" && -n "$LOGISTICS_IP" ]]; then
    echo "  Updating UI configuration with LoadBalancer IPs..."
    cat > /tmp/loadbalancer-ips.yaml <<EOF
services:
  ui:
    config:
      exchangeAppApiUrl: "http://$EXCHANGE_IP:8000"
      logisticsAppApiUrl: "http://$LOGISTICS_IP:9090"
EOF

    helm upgrade ${RELEASE_NAME} ./helm \
        --namespace ${NAMESPACE} \
        --values /tmp/loadbalancer-ips.yaml
    
    echo "  Waiting for UI pod to restart..."
    sleep 30
fi

# Step 6: Verify deployment
echo ""
echo "🔍 Step 6: Verifying deployment..."

# Wait for Grafana to be deployed and fix its security context
echo "  Fixing Grafana security context for OpenShift..."
sleep 10
kubectl patch deployment lungo-grafana -n ${NAMESPACE} --type='json' -p='[{"op": "remove", "path": "/spec/template/spec/securityContext"}]' 2>/dev/null || echo "  Grafana pod-level securityContext already removed"
kubectl patch deployment lungo-grafana -n ${NAMESPACE} --type='json' -p='[{"op": "remove", "path": "/spec/template/spec/containers/0/securityContext"}]' 2>/dev/null || echo "  Grafana container-level securityContext already removed"

# Wait for Grafana to be ready
echo "  Waiting for Grafana to be ready..."
kubectl wait --for=condition=available deployment lungo-grafana -n ${NAMESPACE} --timeout=120s

# Check pod status
echo "  Checking pod status..."
RUNNING_PODS=$(kubectl get pods -n ${NAMESPACE} --field-selector=status.phase=Running --no-headers | wc -l)
TOTAL_PODS=$(kubectl get pods -n ${NAMESPACE} --no-headers | wc -l)

echo "    Pods running: ${RUNNING_PODS}/${TOTAL_PODS}"

# Ensure all expected pods are running
EXPECTED_PODS=17
if [ "$RUNNING_PODS" -ne "$EXPECTED_PODS" ]; then
    echo "    ⚠️  Expected $EXPECTED_PODS pods, but only $RUNNING_PODS are running"
    echo "    Checking pod status..."
    kubectl get pods -n ${NAMESPACE} | grep -v Running
else
    echo "    ✅ All expected pods are running"
fi

# Check LoadBalancer services
echo "  Checking LoadBalancer services..."
kubectl get svc -n ${NAMESPACE} --field-selector spec.type=LoadBalancer

echo ""
echo "🎉 Deployment Complete!"
echo "======================"
echo ""
echo "🌐 Access Points:"
echo "  UI Service:      http://$UI_IP:3000"
echo "  Exchange API:    http://$EXCHANGE_IP:8000"
echo "  Logistics API:   http://$LOGISTICS_IP:9090"
echo "  Grafana:         http://$GRAFANA_IP:80 (admin/admin)"
echo ""
echo "📋 Verification Commands:"
echo "  kubectl get pods -n ${NAMESPACE}"
echo "  kubectl get svc -n ${NAMESPACE}"
echo ""
echo "🧹 To cleanup:"
echo "  ./cleanup.sh"
echo ""
echo "✅ Lungo deployment successful!"
