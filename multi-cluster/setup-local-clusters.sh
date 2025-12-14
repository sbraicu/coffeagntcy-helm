#!/bin/bash
set -e

echo "🏗️  Setting up local kind clusters for Lungo multi-cluster deployment"

# Create backend cluster
echo "🐳 Creating backend cluster..."
kind create cluster --name lungo-backend

# Create frontend cluster  
echo "🐳 Creating frontend cluster..."
kind create cluster --name lungo-frontend

# Install MetalLB on backend cluster
echo "🔧 Installing MetalLB on backend cluster..."
kubectl --context kind-lungo-backend apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

# Install MetalLB on frontend cluster
echo "🔧 Installing MetalLB on frontend cluster..."
kubectl --context kind-lungo-frontend apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

# Wait for MetalLB to be ready
echo "⏳ Waiting for MetalLB to be ready..."
kubectl --context kind-lungo-backend wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s
kubectl --context kind-lungo-frontend wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s

# Configure MetalLB IP pools
echo "📍 Configuring MetalLB IP pools..."

# Backend cluster IP pool
kubectl --context kind-lungo-backend apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: backend-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.18.200.1-172.18.200.50
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: backend-l2
  namespace: metallb-system
EOF

# Frontend cluster IP pool
kubectl --context kind-lungo-frontend apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: frontend-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.18.201.1-172.18.201.50
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: frontend-l2
  namespace: metallb-system
EOF

echo "✅ Local kind clusters ready!"
echo ""
echo "📋 Cluster contexts created:"
echo "  Backend: kind-lungo-backend"
echo "  Frontend: kind-lungo-frontend"
echo ""
echo "🔧 Next steps:"
echo "  1. Set contexts: export BACKEND_CONTEXT=kind-lungo-backend FRONTEND_CONTEXT=kind-lungo-frontend"
echo "  2. Configure LLM settings in values.yaml files"
echo "  3. Run: ./deploy-multi-cluster.sh"
echo ""
echo "🌐 IP ranges assigned:"
echo "  Backend LoadBalancers: 172.18.200.1-172.18.200.50"
echo "  Frontend LoadBalancers: 172.18.201.1-172.18.201.50"
