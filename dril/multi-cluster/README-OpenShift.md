# Multi-Cluster Lungo Deployment for OpenShift

This deployment package provides a fully configurable multi-cluster deployment of the Lungo application on OpenShift clusters.

## Architecture

- **Frontend Cluster**: Hosts UI and Exchange services
- **Backend Cluster**: Hosts ClickHouse, NATS, Logistics services, and Farms

## Configuration

All cluster settings are configurable via environment variables:

```bash
# Copy and edit configuration
cp config.env.example config.env
# Edit config.env with your cluster details
source config.env
```

### Required Configuration

- `FRONTEND_KUBECONFIG`: Path to frontend cluster kubeconfig
- `BACKEND_KUBECONFIG`: Path to backend cluster kubeconfig
- `FRONTEND_IP_POOL_START/END`: IP range for frontend LoadBalancers
- `BACKEND_IP_POOL_START/END`: IP range for backend LoadBalancers

## Quick Start

```bash
# 1. Configure clusters
source config.env

# 2. Deploy multi-cluster
./deploy-openshift-multi-cluster.sh

# 3. Access application
# UI: http://<FRONTEND-IP>:3000
# Exchange: http://<FRONTEND-IP>:8000
```

## Cleanup

```bash
# Use same configuration
source config.env
./cleanup-openshift-multi-cluster.sh
```

## Features

- **Fully Configurable**: No hardcoded cluster names or paths
- **OpenShift Compatible**: Handles SCCs and security contexts
- **MetalLB Integration**: Automatic LoadBalancer setup
- **Cross-Cluster Communication**: Backend services exposed to frontend
- **Complete Cleanup**: Restores clusters to initial state

## Verification

```bash
# Check frontend cluster
KUBECONFIG=$FRONTEND_KUBECONFIG kubectl get pods -n $FRONTEND_NAMESPACE

# Check backend cluster  
KUBECONFIG=$BACKEND_KUBECONFIG kubectl get pods -n $BACKEND_NAMESPACE
```

## Troubleshooting

### ClickHouse Pod Stuck in ContainerCreating
The script automatically creates the required storage directory. If issues persist:
```bash
# Manually create storage directory on worker node
KUBECONFIG=$BACKEND_KUBECONFIG kubectl debug node/<worker-node> -it --image=busybox -- mkdir -p /host/tmp/clickhouse-data
```

### Cross-Cluster Connectivity Issues
Verify LoadBalancer IPs are assigned:
```bash
KUBECONFIG=$BACKEND_KUBECONFIG kubectl get svc -n $BACKEND_NAMESPACE | grep LoadBalancer
```
