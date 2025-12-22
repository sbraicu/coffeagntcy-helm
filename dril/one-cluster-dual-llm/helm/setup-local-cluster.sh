#!/bin/bash
set -e

echo "🏗️  Setting up local kind cluster for Lungo one-cluster deployment"

# Create kind cluster
echo "🐳 Creating kind cluster..."
kind create cluster --name lungo

# Install MetalLB for LoadBalancer support
echo "🔧 Installing MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

# Wait for MetalLB to be ready
echo "⏳ Waiting for MetalLB to be ready..."
sleep 30
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s

# Configure MetalLB IP pool
echo "📍 Configuring MetalLB IP pool..."
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lungo-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.18.255.1-172.18.255.50
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lungo-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - lungo-pool
EOF

echo "✅ Local kind cluster ready!"
echo ""
echo "📋 Cluster context created: kind-lungo"
echo ""
echo "🔧 Next steps:"
echo "  1. Configure LLM settings in values.yaml"
echo "  2. Run: ./deploy-chart.sh"
echo ""
echo "🌐 IP range assigned:"
echo "  LoadBalancers: 172.18.255.1-172.18.255.50"
