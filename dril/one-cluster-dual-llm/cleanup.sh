#!/bin/bash
set -e

echo "🧹 Cleaning up Lungo deployment..."
echo "============================================"

NAMESPACE="lungo"
RELEASE_NAME="lungo"

# Step 1: Uninstall Helm release
echo "📦 Uninstalling Helm release..."
helm uninstall ${RELEASE_NAME} -n ${NAMESPACE} 2>/dev/null || echo "  Release not found or already removed"

# Step 2: Delete namespace
echo "🗂️  Deleting namespace..."
kubectl delete namespace ${NAMESPACE} 2>/dev/null || echo "  Namespace not found or already removed"

# Step 3: Remove Security Context Constraints
echo "🔒 Removing Security Context Constraints..."
kubectl delete scc metallb-speaker metallb-controller 2>/dev/null || echo "  MetalLB SCCs not found"

# Step 4: Clean up MetalLB configuration
echo "🔧 Cleaning up MetalLB configuration..."
kubectl delete ipaddresspool default-pool -n metallb-system 2>/dev/null || echo "  IP pool not found"
kubectl delete l2advertisement default-l2advertisement -n metallb-system 2>/dev/null || echo "  L2 advertisement not found"

# Step 5: Remove MetalLB completely
echo "🗑️  Removing MetalLB installation..."
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml 2>/dev/null || echo "  MetalLB not found or already removed"

# Step 6: Remove storage resources
echo "💾 Removing storage resources..."
kubectl delete pv clickhouse-pv 2>/dev/null || echo "  PV not found"
kubectl delete storageclass local-storage 2>/dev/null || echo "  StorageClass not found"

# Step 7: Clean up storage directory (optional)
echo "🗑️  Cleaning up storage directory..."
WORKER_NODE=$(kubectl get nodes --selector='!node-role.kubernetes.io/master' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$WORKER_NODE" ]; then
    kubectl debug node/${WORKER_NODE} -it --image=busybox -- rm -rf /host/tmp/clickhouse-data 2>/dev/null || echo "  Storage directory cleanup skipped"
fi

# Step 8: Remove temporary files
echo "📄 Removing temporary files..."
rm -f /tmp/loadbalancer-ips.yaml 2>/dev/null || true
rm -f /tmp/cluster_state_backup.yaml 2>/dev/null || true

echo ""
echo "✅ Cleanup completed!"
echo ""
echo "📋 Verification:"
echo "  kubectl get pods -n ${NAMESPACE}  # Should show 'No resources found'"
echo "  kubectl get pv,pvc                # Should not show lungo-related resources"
echo "  kubectl get scc | grep metallb    # Should not show metallb SCCs"
echo ""
echo "🔄 Cluster restored to initial state"
