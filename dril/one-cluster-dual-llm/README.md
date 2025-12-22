# Lungo Deployment for OpenShift

This deployment package contains all necessary fixes and configurations to deploy the Lungo application on OpenShift clusters.

## Prerequisites

- OpenShift cluster with admin access
- Helm 3.x installed
- kubectl/oc CLI configured
- MetalLB or equivalent LoadBalancer provider

## Quick Start

```bash
# 1. Set your kubeconfig
export KUBECONFIG=/path/to/your/kubeconfig

# 2. Run the deployment script
./deploy-openshift.sh

# 3. Access the application
# UI: http://<EXTERNAL-IP>:3000
# Exchange: http://<EXTERNAL-IP>:8000
# Logistics: http://<EXTERNAL-IP>:9090
# Grafana: http://<EXTERNAL-IP>:80 (admin/admin)
```

## What This Deployment Includes

### Infrastructure Components
- **MetalLB**: LoadBalancer provider for OpenShift
- **Local Storage**: PersistentVolume support for ClickHouse
- **Security Context Constraints**: Proper SCCs for OpenShift security

### Application Components
- **ClickHouse**: Database backend
- **NATS**: Message broker
- **OpenTelemetry**: Observability collector
- **Grafana**: Monitoring dashboard
- **Lungo Services**: UI, Exchange, Logistics, Farms, MCP server

### OpenShift-Specific Fixes
1. **MetalLB SCCs**: Custom security contexts for MetalLB components
2. **Application SCCs**: anyuid SCC for application containers
3. **Storage Class**: Local storage provisioner
4. **Security Context Removal**: Removed restrictive container security contexts
5. **Permission Fixes**: Resolved cache directory permission issues

## Files Structure

```
openshift-lungo-deployment/
├── README.md                    # This file
├── deploy-openshift.sh          # Main deployment script
├── cleanup.sh                   # Cleanup script
├── configs/
│   ├── metallb-scc.yaml        # MetalLB Security Context Constraints
│   ├── local-storage.yaml      # Local StorageClass and PV
│   └── metallb-config.yaml     # MetalLB IP pool configuration
├── helm/
│   ├── Chart.yaml              # Modified Helm chart
│   ├── values-openshift.yaml   # OpenShift-specific values
│   └── templates/              # Modified templates without securityContext
└── docs/
    ├── troubleshooting.md      # Common issues and solutions
    └── architecture.md         # Deployment architecture
```

## Deployment Process

The deployment script performs these steps:

1. **Install MetalLB** with proper OpenShift SCCs
2. **Configure Storage** with local StorageClass and PersistentVolume
3. **Setup Security** with anyuid SCC for applications
4. **Deploy Application** using modified Helm chart
5. **Configure LoadBalancer IPs** automatically
6. **Verify Deployment** and provide access URLs

## Troubleshooting

### Common Issues

1. **Pods stuck in Pending**: Check PVC binding and storage availability
2. **Permission Denied errors**: Verify anyuid SCC is applied
3. **LoadBalancer IPs not assigned**: Check MetalLB configuration and IP pool
4. **Security Context errors**: Ensure securityContext is removed from pod specs

### Verification Commands

```bash
# Check pod status
kubectl get pods -n lungo

# Check LoadBalancer services
kubectl get svc -n lungo --field-selector spec.type=LoadBalancer

# Check MetalLB status
kubectl get pods -n metallb-system

# Check storage
kubectl get pv,pvc -n lungo
```

## Cleanup

To remove the deployment and restore cluster state:

```bash
./cleanup.sh
```

This will:
- Uninstall the Helm release
- Delete the namespace
- Remove custom SCCs
- Clean up MetalLB configuration
- Remove storage resources

## Support

For issues or questions:
1. Check the troubleshooting guide
2. Verify all prerequisites are met
3. Check OpenShift cluster permissions
4. Review pod logs for specific errors
