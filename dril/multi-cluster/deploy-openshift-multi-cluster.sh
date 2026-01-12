#!/bin/bash
set -e

echo "🚀 Deploying Lungo Multi-Cluster Architecture on OpenShift"
echo "=========================================================="

# Configuration - Make these configurable via environment variables
FRONTEND_KUBECONFIG="${FRONTEND_KUBECONFIG:-/home/cisco/aipod3_new/auth/kubeconfig}"
BACKEND_KUBECONFIG="${BACKEND_KUBECONFIG:-/home/cisco/aipod4_new/auth/kubeconfig}"
BACKEND_NAMESPACE="${BACKEND_NAMESPACE:-lungo-backend}"
FRONTEND_NAMESPACE="${FRONTEND_NAMESPACE:-lungo-frontend}"
METALLB_VERSION="${METALLB_VERSION:-v0.14.8}"
BACKEND_IP_POOL_START="${BACKEND_IP_POOL_START:-10.100.100.210}"
BACKEND_IP_POOL_END="${BACKEND_IP_POOL_END:-10.100.100.220}"
FRONTEND_IP_POOL_START="${FRONTEND_IP_POOL_START:-10.100.100.200}"
FRONTEND_IP_POOL_END="${FRONTEND_IP_POOL_END:-10.100.100.209}"

echo "📋 Configuration:"
echo "  Frontend Cluster: ${FRONTEND_KUBECONFIG}"
echo "  Backend Cluster: ${BACKEND_KUBECONFIG}"
echo "  Frontend Namespace: ${FRONTEND_NAMESPACE}"
echo "  Backend Namespace: ${BACKEND_NAMESPACE}"
echo ""

# Function to setup cluster infrastructure
setup_cluster_infrastructure() {
    local KUBECONFIG_PATH=$1
    local CLUSTER_NAME=$2
    local IP_POOL_START=$3
    local IP_POOL_END=$4
    
    echo "🔧 Setting up infrastructure for $CLUSTER_NAME..."
    
    # Create MetalLB SCCs
    echo "  Creating MetalLB Security Context Constraints..."
    KUBECONFIG=$KUBECONFIG_PATH kubectl apply -f - <<EOF
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: metallb-speaker
allowHostDirVolumePlugin: true
allowHostIPC: false
allowHostNetwork: true
allowHostPID: false
allowHostPorts: true
allowPrivilegedContainer: true
allowedCapabilities:
- NET_RAW
defaultAddCapabilities: []
fsGroup:
  type: RunAsAny
readOnlyRootFilesystem: false
requiredDropCapabilities: []
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: RunAsAny
supplementalGroups:
  type: RunAsAny
users:
- system:serviceaccount:metallb-system:speaker
volumes:
- configMap
- downwardAPI
- emptyDir
- hostPath
- projected
- secret
---
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: metallb-controller
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegedContainer: false
allowedCapabilities: []
defaultAddCapabilities: []
fsGroup:
  type: RunAsAny
readOnlyRootFilesystem: false
requiredDropCapabilities: []
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: RunAsAny
supplementalGroups:
  type: RunAsAny
users:
- system:serviceaccount:metallb-system:controller
volumes:
- configMap
- downwardAPI
- emptyDir
- projected
- secret
EOF

    # Create application SCCs
    echo "  Creating application Security Context Constraints..."
    KUBECONFIG=$KUBECONFIG_PATH kubectl apply -f - <<EOF
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: lungo-anyuid-scc
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegedContainer: false
allowedCapabilities: null
defaultAddCapabilities: null
fsGroup:
  type: RunAsAny
readOnlyRootFilesystem: false
requiredDropCapabilities:
- MKNOD
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: RunAsAny
supplementalGroups:
  type: RunAsAny
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
priority: 10
---
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: grafana-scc
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegedContainer: false
allowedCapabilities: null
defaultAddCapabilities: null
fsGroup:
  type: RunAsAny
readOnlyRootFilesystem: false
requiredDropCapabilities:
- MKNOD
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: RunAsAny
supplementalGroups:
  type: RunAsAny
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
seccompProfiles:
- runtime/default
- unconfined
priority: 10
EOF

    # Install MetalLB
    echo "  Installing MetalLB components..."
    KUBECONFIG=$KUBECONFIG_PATH kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml

    # Wait for MetalLB to be ready
    echo "  Waiting for MetalLB to be ready..."
    KUBECONFIG=$KUBECONFIG_PATH kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=120s

    # Configure MetalLB IP pool
    echo "  Configuring MetalLB IP pool..."
    KUBECONFIG=$KUBECONFIG_PATH kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - ${IP_POOL_START}-${IP_POOL_END}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-l2advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
EOF

    # Setup storage for backend cluster (ClickHouse)
    if [ "$CLUSTER_NAME" = "Backend" ]; then
        echo "  Setting up storage for ClickHouse..."
        
        # Get worker node name first
        WORKER_NODE=$(KUBECONFIG=$KUBECONFIG_PATH kubectl get nodes --selector='!node-role.kubernetes.io/master' -o jsonpath='{.items[0].metadata.name}')
        echo "  Using worker node: $WORKER_NODE"
        
        # Create storage class first
        KUBECONFIG=$KUBECONFIG_PATH kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF

        # Create PV with substituted worker node name
        cat <<EOF | KUBECONFIG=$KUBECONFIG_PATH kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: clickhouse-pv
spec:
  capacity:
    storage: 8Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  storageClassName: local-storage
  local:
    path: /tmp/clickhouse-data
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $WORKER_NODE
EOF
        
        # Create storage directory
        echo "  Creating storage directory on worker node..."
        KUBECONFIG=$KUBECONFIG_PATH kubectl debug node/${WORKER_NODE} -it --image=busybox -- mkdir -p /host/tmp/clickhouse-data || true
    fi
    
    # Assign SCCs to service accounts
    echo "  Assigning Security Context Constraints..."
    if [ "$CLUSTER_NAME" = "Frontend" ]; then
        # SCCs will be assigned after helm install
        echo "  Frontend SCCs will be assigned after deployment"
    else
        KUBECONFIG=$KUBECONFIG_PATH oc adm policy add-scc-to-group lungo-anyuid-scc system:serviceaccounts:lungo-backend
    fi
    
    echo "✅ Infrastructure setup completed for $CLUSTER_NAME"
}

# Deploy Backend Cluster
echo ""
echo "🔧 Step 1: Deploying Backend Cluster..."
setup_cluster_infrastructure "$BACKEND_KUBECONFIG" "Backend" "$BACKEND_IP_POOL_START" "$BACKEND_IP_POOL_END"

cd cluster-1-backend

echo "📦 Adding Helm repositories..."
helm repo add external-secrets https://charts.external-secrets.io
helm repo add nats https://nats-io.github.io/k8s/helm/charts
helm repo add opentelemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

echo "⚡ Installing backend services..."
# Check if charts already exist to avoid rate limit issues
if [ ! -d "charts" ] || [ -z "$(ls -A charts 2>/dev/null)" ]; then
    echo "Downloading dependencies..."
    helm dependency update .
else
    echo "Using existing charts..."
fi

# Setup security context constraints for backend
KUBECONFIG=$BACKEND_KUBECONFIG oc adm policy add-scc-to-user anyuid -z default -n $BACKEND_NAMESPACE || KUBECONFIG=$BACKEND_KUBECONFIG kubectl create namespace $BACKEND_NAMESPACE
KUBECONFIG=$BACKEND_KUBECONFIG oc adm policy add-scc-to-user anyuid -z default -n $BACKEND_NAMESPACE

KUBECONFIG=$BACKEND_KUBECONFIG helm install lungo-backend . \
  --create-namespace --namespace $BACKEND_NAMESPACE

echo "⏳ Waiting for backend core services..."
KUBECONFIG=$BACKEND_KUBECONFIG kubectl wait --for=condition=ready pod lungo-backend-clickhouse-shard0-0 -n $BACKEND_NAMESPACE --timeout=300s

# Fix security contexts for backend services
echo "🔒 Fixing security contexts for backend services..."
sleep 10
for deployment in $(KUBECONFIG=$BACKEND_KUBECONFIG kubectl get deployments -n $BACKEND_NAMESPACE -o name | grep -v external-secrets); do
    KUBECONFIG=$BACKEND_KUBECONFIG kubectl patch $deployment -n $BACKEND_NAMESPACE --type='json' -p='[{"op": "remove", "path": "/spec/template/spec/containers/0/securityContext"}]' 2>/dev/null || true
done

echo "⏳ Waiting for backend services to be ready..."
sleep 30

# Patch NATS and SLIM services to LoadBalancer for cross-cluster communication
echo "🔗 Configuring backend services for cross-cluster access..."
KUBECONFIG=$BACKEND_KUBECONFIG kubectl patch service lungo-backend-nats -n $BACKEND_NAMESPACE -p '{"spec":{"type":"LoadBalancer"}}'
KUBECONFIG=$BACKEND_KUBECONFIG kubectl patch service lungo-backend-slim -n $BACKEND_NAMESPACE -p '{"spec":{"type":"LoadBalancer"}}'

echo "⏳ Waiting for LoadBalancer IPs..."
sleep 30

# Get backend service endpoints
echo "🔍 Getting backend service endpoints..."
NATS_IP=$(KUBECONFIG=$BACKEND_KUBECONFIG kubectl get svc -n $BACKEND_NAMESPACE lungo-backend-nats -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
OTEL_IP=$(KUBECONFIG=$BACKEND_KUBECONFIG kubectl get svc -n $BACKEND_NAMESPACE lungo-backend-opentelemetry-collector -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
CLICKHOUSE_IP=$(KUBECONFIG=$BACKEND_KUBECONFIG kubectl get svc -n $BACKEND_NAMESPACE lungo-backend-clickhouse -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
SLIM_LB_IP=$(KUBECONFIG=$BACKEND_KUBECONFIG kubectl get svc -n $BACKEND_NAMESPACE lungo-backend-slim -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

# Wait for LoadBalancer IPs
echo "⏳ Waiting for backend LoadBalancer IPs..."
for i in {1..30}; do
    NATS_IP=$(KUBECONFIG=$BACKEND_KUBECONFIG kubectl get svc -n $BACKEND_NAMESPACE lungo-backend-nats -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    SLIM_LB_IP=$(KUBECONFIG=$BACKEND_KUBECONFIG kubectl get svc -n $BACKEND_NAMESPACE lungo-backend-slim -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [[ -n "$NATS_IP" && -n "$SLIM_LB_IP" ]]; then
        break
    fi
    echo "  Waiting for backend LoadBalancer IPs... ($i/30)"
    sleep 10
done

# Wait for backend LoadBalancer IPs
echo "⏳ Waiting for backend LoadBalancer IPs..."
for i in {1..30}; do
    NATS_IP=$(KUBECONFIG=$BACKEND_KUBECONFIG kubectl get svc -n $BACKEND_NAMESPACE lungo-backend-nats -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    SLIM_LB_IP=$(KUBECONFIG=$BACKEND_KUBECONFIG kubectl get svc -n $BACKEND_NAMESPACE lungo-backend-slim -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [[ -n "$NATS_IP" && -n "$SLIM_LB_IP" ]]; then
        break
    fi
    echo "  Waiting for backend LoadBalancer IPs... ($i/30)"
    sleep 10
done

# Wait for all backend LoadBalancer IPs to be available
echo "⏳ Waiting for all backend LoadBalancer IPs..."
for i in {1..60}; do
    NATS_IP=$(KUBECONFIG=$BACKEND_KUBECONFIG kubectl get svc -n $BACKEND_NAMESPACE lungo-backend-nats -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    OTEL_IP=$(KUBECONFIG=$BACKEND_KUBECONFIG kubectl get svc -n $BACKEND_NAMESPACE lungo-backend-opentelemetry-collector -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    CLICKHOUSE_IP=$(KUBECONFIG=$BACKEND_KUBECONFIG kubectl get svc -n $BACKEND_NAMESPACE lungo-backend-clickhouse -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    SLIM_LB_IP=$(KUBECONFIG=$BACKEND_KUBECONFIG kubectl get svc -n $BACKEND_NAMESPACE lungo-backend-slim -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [[ -n "$NATS_IP" && -n "$OTEL_IP" && -n "$CLICKHOUSE_IP" && -n "$SLIM_LB_IP" ]]; then
        echo "  All backend LoadBalancer IPs ready:"
        echo "    NATS: $NATS_IP"
        echo "    OpenTelemetry: $OTEL_IP" 
        echo "    ClickHouse: $CLICKHOUSE_IP"
        echo "    SLIM: $SLIM_LB_IP"
        break
    fi
    echo "  Waiting for backend LoadBalancer IPs... ($i/60)"
    sleep 10
done

if [[ -z "$NATS_IP" || -z "$OTEL_IP" || -z "$CLICKHOUSE_IP" || -z "$SLIM_LB_IP" ]]; then
    echo "❌ Failed to get all backend LoadBalancer IPs after 10 minutes"
    exit 1
fi

echo "✅ Backend cluster deployed successfully"
echo "  NATS IP: $NATS_IP"
echo "  SLIM IP: $SLIM_LB_IP"

# Deploy Frontend Cluster
echo ""
echo "🔧 Step 2: Deploying Frontend Cluster..."
setup_cluster_infrastructure "$FRONTEND_KUBECONFIG" "Frontend" "$FRONTEND_IP_POOL_START" "$FRONTEND_IP_POOL_END"

cd ../cluster-2-frontend

echo "📦 Adding Helm repositories for frontend..."
helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
timeout 120 helm repo update

echo "⚡ Installing frontend services..."
# Check if charts already exist to avoid rate limit issues
if [ ! -d "charts" ] || [ -z "$(ls -A charts 2>/dev/null)" ]; then
    echo "Downloading dependencies..."
    timeout 300 helm dependency update .
else
    echo "Using existing charts..."
fi

# Setup security context constraints for frontend
KUBECONFIG=$FRONTEND_KUBECONFIG oc adm policy add-scc-to-user anyuid -z default -n $FRONTEND_NAMESPACE || KUBECONFIG=$FRONTEND_KUBECONFIG kubectl create namespace $FRONTEND_NAMESPACE
KUBECONFIG=$FRONTEND_KUBECONFIG oc adm policy add-scc-to-user anyuid -z default -n $FRONTEND_NAMESPACE

echo "⚡ Installing frontend application..."
# Create backend endpoints configuration file in chart directory
cat > backend-endpoints.yaml <<EOF
transport:
  nats:
    endpoint: "nats://$NATS_IP:4222"
    type: "NATS"
  slim:
    endpoint: "http://$SLIM_LB_IP:46357"

observability:
  otlpEndpoint: "http://$OTEL_IP:4318"

global:
  backendCluster:
    natsEndpoint: "nats://$NATS_IP:4222"
    slimEndpoint: "http://$SLIM_LB_IP:46357"
    otlpEndpoint: "http://$OTEL_IP:4318"
    clickhouseEndpoint: "http://$CLICKHOUSE_IP:8123"
EOF

# Create frontend LoadBalancer configuration file in chart directory
cat > frontend-lb-config.yaml <<EOF
serviceType: LoadBalancer
grafana:
  service:
    type: LoadBalancer
    port: 80
EOF

KUBECONFIG=$FRONTEND_KUBECONFIG helm install lungo-frontend . \
  --create-namespace --namespace $FRONTEND_NAMESPACE \
  --values backend-endpoints.yaml \
  --values frontend-lb-config.yaml

if [ $? -ne 0 ]; then
    echo "❌ Frontend helm install failed"
    exit 1
fi

echo "✅ Frontend application installed successfully"

# Add Grafana Security Context Constraints
echo "🔒 Adding Grafana Security Context Constraints..."
KUBECONFIG=$FRONTEND_KUBECONFIG oc adm policy add-scc-to-group lungo-anyuid-scc system:serviceaccounts:lungo-frontend
KUBECONFIG=$FRONTEND_KUBECONFIG oc adm policy add-scc-to-user grafana-scc -z lungo-frontend-grafana -n $FRONTEND_NAMESPACE
KUBECONFIG=$FRONTEND_KUBECONFIG oc adm policy add-scc-to-user anyuid -z lungo-frontend-grafana -n $FRONTEND_NAMESPACE

# Add Grafana Security Context Constraints
echo "🔒 Adding Grafana Security Context Constraints..."
KUBECONFIG=$FRONTEND_KUBECONFIG oc adm policy add-scc-to-user grafana-scc -z lungo-frontend-grafana -n $FRONTEND_NAMESPACE
KUBECONFIG=$FRONTEND_KUBECONFIG oc adm policy add-scc-to-user anyuid -z lungo-frontend-grafana -n $FRONTEND_NAMESPACE

# Fix security contexts for frontend services
echo "🔒 Fixing security contexts for frontend services..."
sleep 10
for deployment in $(KUBECONFIG=$FRONTEND_KUBECONFIG kubectl get deployments -n $FRONTEND_NAMESPACE -o name | grep -v external-secrets); do
    KUBECONFIG=$FRONTEND_KUBECONFIG kubectl patch $deployment -n $FRONTEND_NAMESPACE --type='json' -p='[{"op": "remove", "path": "/spec/template/spec/containers/0/securityContext"}]' 2>/dev/null || true
done

echo "⏳ Waiting for frontend services to be ready..."
sleep 30

# Get frontend service endpoints
echo "🔍 Getting frontend service endpoints..."
UI_IP=$(KUBECONFIG=$FRONTEND_KUBECONFIG kubectl get svc -n $FRONTEND_NAMESPACE lungo-ui -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
EXCHANGE_IP=$(KUBECONFIG=$FRONTEND_KUBECONFIG kubectl get svc -n $FRONTEND_NAMESPACE lungo-exchange -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

# Wait for frontend LoadBalancer IPs
echo "⏳ Waiting for frontend LoadBalancer IPs..."
for i in {1..30}; do
    UI_IP=$(KUBECONFIG=$FRONTEND_KUBECONFIG kubectl get svc -n $FRONTEND_NAMESPACE lungo-ui -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    EXCHANGE_IP=$(KUBECONFIG=$FRONTEND_KUBECONFIG kubectl get svc -n $FRONTEND_NAMESPACE lungo-exchange -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [[ -n "$UI_IP" && -n "$EXCHANGE_IP" ]]; then
        break
    fi
    echo "  Waiting for frontend LoadBalancer IPs... ($i/30)"
    sleep 10
done

echo "✅ Frontend cluster deployed successfully"

# Final verification
echo ""
echo "🔍 Step 3: Verifying multi-cluster deployment..."

BACKEND_PODS=$(KUBECONFIG=$BACKEND_KUBECONFIG kubectl get pods -n $BACKEND_NAMESPACE --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
FRONTEND_PODS=$(KUBECONFIG=$FRONTEND_KUBECONFIG kubectl get pods -n $FRONTEND_NAMESPACE --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

echo "  Backend pods running: $BACKEND_PODS"
echo "  Frontend pods running: $FRONTEND_PODS"

# Test cross-cluster connectivity
echo "🔗 Testing cross-cluster connectivity..."
if [[ -n "$NATS_IP" ]]; then
    KUBECONFIG=$FRONTEND_KUBECONFIG kubectl run connectivity-test --rm -i --image=busybox --restart=Never -n $FRONTEND_NAMESPACE -- nc -zv $NATS_IP 4222 2>/dev/null && echo "  ✅ Cross-cluster connectivity working" || echo "  ⚠️  Cross-cluster connectivity test failed"
else
    echo "  ⚠️  NATS IP not available for connectivity test"
fi

echo ""
echo "🎉 Multi-cluster deployment completed!"
echo ""
echo "📋 Access URLs:"
echo "  UI: http://$UI_IP:3000"
echo "  Exchange: http://$EXCHANGE_IP:8000"
GRAFANA_IP=$(KUBECONFIG=$FRONTEND_KUBECONFIG kubectl get svc -n $FRONTEND_NAMESPACE lungo-frontend-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
echo "  Grafana: http://$GRAFANA_IP:80"

echo ""
echo "🎉 Multi-Cluster Deployment Complete!"
echo "====================================="
echo ""
echo "🌐 Access Points:"
echo "  UI Service:      http://$UI_IP:3000"
echo "  Exchange API:    http://$EXCHANGE_IP:8000"
echo ""
echo "🔧 Backend Services (Backend cluster):"
echo "  NATS:           $NATS_IP:4222"
echo "  SLIM:           $SLIM_LB_IP:46357"
echo "  ClickHouse:     $CLICKHOUSE_IP:8123"
echo "  OpenTelemetry:  $OTEL_IP:4318"
echo ""
echo "📋 Verification Commands:"
echo "  # Frontend cluster (Frontend cluster)"
echo "  KUBECONFIG=$FRONTEND_KUBECONFIG kubectl get pods -n $FRONTEND_NAMESPACE"
echo "  # Backend cluster (Backend cluster)"
echo "  KUBECONFIG=$BACKEND_KUBECONFIG kubectl get pods -n $BACKEND_NAMESPACE"
echo ""
echo "✅ Multi-cluster Lungo deployment successful!"
