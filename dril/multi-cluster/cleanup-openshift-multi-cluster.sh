#!/bin/bash
set -e

echo "🧹 Cleaning up Multi-Cluster Lungo deployment..."
echo "==============================================="

# Configuration - Make these configurable via environment variables
FRONTEND_KUBECONFIG="${FRONTEND_KUBECONFIG:-/home/cisco/aipod3_new/auth/kubeconfig}"
BACKEND_KUBECONFIG="${BACKEND_KUBECONFIG:-/home/cisco/aipod4_new/auth/kubeconfig}"
BACKEND_NAMESPACE="${BACKEND_NAMESPACE:-lungo-backend}"
FRONTEND_NAMESPACE="${FRONTEND_NAMESPACE:-lungo-frontend}"
METALLB_VERSION="${METALLB_VERSION:-v0.14.8}"

# Function to cleanup cluster
cleanup_cluster() {
    local KUBECONFIG_PATH=$1
    local NAMESPACE=$2
    local RELEASE_NAME=$3
    local CLUSTER_NAME=$4
    
    echo "🧹 Cleaning up $CLUSTER_NAME cluster..."
    
    # Uninstall Helm release
    echo "  Uninstalling Helm release..."
    KUBECONFIG=$KUBECONFIG_PATH helm uninstall $RELEASE_NAME -n $NAMESPACE 2>/dev/null || echo "  Release not found or already removed"
    
    # Delete namespace
    echo "  Deleting namespace..."
    KUBECONFIG=$KUBECONFIG_PATH kubectl delete namespace $NAMESPACE 2>/dev/null || echo "  Namespace not found or already removed"
    
    # Remove Security Context Constraints
    echo "  Removing Security Context Constraints..."
    KUBECONFIG=$KUBECONFIG_PATH kubectl delete scc metallb-speaker metallb-controller 2>/dev/null || echo "  MetalLB SCCs not found"
    
    # Clean up MetalLB configuration
    echo "  Cleaning up MetalLB configuration..."
    KUBECONFIG=$KUBECONFIG_PATH kubectl delete ipaddresspool default-pool -n metallb-system 2>/dev/null || echo "  IP pool not found"
    KUBECONFIG=$KUBECONFIG_PATH kubectl delete l2advertisement default-l2advertisement -n metallb-system 2>/dev/null || echo "  L2 advertisement not found"
    
    # Remove MetalLB completely
    echo "  Removing MetalLB installation..."
    KUBECONFIG=$KUBECONFIG_PATH kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml 2>/dev/null || echo "  MetalLB not found or already removed"
    
    # Remove storage resources (backend only)
    if [ "$CLUSTER_NAME" = "Backend" ]; then
        echo "  Removing storage resources..."
        KUBECONFIG=$KUBECONFIG_PATH kubectl delete pv clickhouse-pv 2>/dev/null || echo "  PV not found"
        KUBECONFIG=$KUBECONFIG_PATH kubectl delete storageclass local-storage 2>/dev/null || echo "  StorageClass not found"
        
        # Clean up storage directory
        echo "  Cleaning up storage directory..."
        WORKER_NODE=$(KUBECONFIG=$KUBECONFIG_PATH kubectl get nodes --selector='!node-role.kubernetes.io/master' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$WORKER_NODE" ]; then
            KUBECONFIG=$KUBECONFIG_PATH kubectl debug node/${WORKER_NODE} -it --image=busybox -- rm -rf /host/tmp/clickhouse-data 2>/dev/null || echo "  Storage directory cleanup skipped"
        fi
    fi
    
    echo "✅ $CLUSTER_NAME cluster cleanup completed"
}

# Clean up backend cluster (Backend cluster)
cleanup_cluster "$BACKEND_KUBECONFIG" "$BACKEND_NAMESPACE" "lungo-backend" "Backend"

# Clean up frontend cluster (Frontend cluster)  
cleanup_cluster "$FRONTEND_KUBECONFIG" "$FRONTEND_NAMESPACE" "lungo-frontend" "Frontend"

# Remove temporary files
echo "📄 Removing temporary files..."
rm -f /tmp/frontend-backend-config.yaml 2>/dev/null || true

echo ""
echo "✅ Multi-cluster cleanup completed!"
echo ""
echo "📋 Verification:"
echo "  # Frontend cluster (Frontend cluster)"
echo "  KUBECONFIG=$FRONTEND_KUBECONFIG kubectl get pods -n $FRONTEND_NAMESPACE  # Should show 'No resources found'"
echo "  # Backend cluster (Backend cluster)"
echo "  KUBECONFIG=$BACKEND_KUBECONFIG kubectl get pods -n $BACKEND_NAMESPACE  # Should show 'No resources found'"
echo ""
echo "🔄 Both clusters restored to initial state"
