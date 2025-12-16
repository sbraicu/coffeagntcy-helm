# Lungo Multi-Cluster Deployment Guide

Deploy Lungo across two Kubernetes clusters with separate LLM configurations.

## 1. Configuration Required

### Set Cluster Contexts
```bash
export BACKEND_CONTEXT="your-backend-cluster-context"
export FRONTEND_CONTEXT="your-frontend-cluster-context"
```

### Configure Backend LLM
Edit `cluster-1-backend/values.yaml`:

**Option A: Direct Configuration (Development)**
```yaml
llm:
  model: "azure/your-deployment-name"          # ← CHANGE: Provider/model
  apiKey: "your-backend-api-key"              # ← CHANGE: Your API key
  apiBase: "https://your-resource.openai.azure.com/"  # ← CHANGE: Your endpoint
  apiVersion: "2024-02-15-preview"            # ← CHANGE: API version
  temperature: 0.7                            # ← OPTIONAL: Adjust as needed
```

**Option B: External Secrets (Production)**
```yaml
# Enable external secrets for backend
externalSecrets:
  secretStoreName: "aws-secrets-manager"
  secretStoreKind: "SecretStore"
  data:
    - secretKey: "llm-api-key"
      remoteRef:
        key: "lungo/backend-llm-key"

llm:
  model: "azure/your-deployment-name"
  apiKey: ""                                  # Will come from external secret
  apiBase: "https://your-resource.openai.azure.com/"
  apiVersion: "2024-02-15-preview"
  temperature: 0.7
```

### Configure Frontend LLM
Edit `cluster-2-frontend/values.yaml`:

**Option A: Direct Configuration (Development)**
```yaml
llm:
  model: "azure/your-deployment-name"                  # ← CHANGE: Provider/model
  apiKey: "your-frontend-api-key"                     # ← CHANGE: Your API key
  apiBase: "https://your-resource.openai.azure.com/"  # ← CHANGE: Your endpoint
  apiVersion: "2024-02-15-preview"                    # ← CHANGE: API version
  temperature: 0.7                                    # ← OPTIONAL: Adjust as needed
```

**Option B: External Secrets (Production)**
```yaml
# Enable external secrets for frontend
externalSecrets:
  secretStoreName: "azure-key-vault"
  secretStoreKind: "SecretStore"
  data:
    - secretKey: "llm-api-key"
      remoteRef:
        key: "lungo-frontend-llm-key"

llm:
  model: "azure/your-deployment-name"
  apiKey: ""                                          # Will come from external secret
  apiBase: "https://your-resource.openai.azure.com/"
  apiVersion: "2024-02-15-preview"
  temperature: 0.7
```

**Other LLM Providers:**
```yaml
# OpenAI
llm:
  model: "openai/gpt-4"
  apiKey: "your-openai-api-key"
  apiBase: "https://api.openai.com/v1"  # Optional, this is default
  temperature: 0.7

# GROQ
llm:
  model: "groq/llama-3.1-70b-versatile"
  apiKey: "your-groq-api-key"
  apiBase: "https://api.groq.com/openai/v1"  # Optional, this is default
  temperature: 0.7

# Local LLM (OpenAI-compatible)
llm:
  model: "openai/your-local-model"
  apiKey: "not-needed"
  apiBase: "http://localhost:8080/v1"
  temperature: 0.7
```

## External Secrets (Production)

For production deployments, External Secrets can integrate with your existing secret management infrastructure.

### Prerequisites
- Existing secret management system in each cluster
- External Secrets Operator installed in both clusters  
- SecretStores configured for your secret management systems

### Setup
1. **Store API keys in your existing secret management systems**
2. **Ensure SecretStores are configured in both clusters**
3. **Uncomment `externalSecrets` sections in values.yaml files**
4. **Deploy with `./deploy-multi-cluster.sh`**

The LLM_API_KEY will be sourced from your external secret stores instead of values.yaml.

## 2. Automated Deployment

### For Local Testing (Kind Clusters)

**Setup local clusters:**
```bash
./setup-local-clusters.sh
```

**Set contexts and deploy:**
```bash
export BACKEND_CONTEXT=kind-lungo-backend
export FRONTEND_CONTEXT=kind-lungo-frontend
./deploy-multi-cluster.sh
```

### For Existing Clusters

**Set your cluster contexts and deploy:**
```bash
export BACKEND_CONTEXT="your-backend-cluster-context"
export FRONTEND_CONTEXT="your-frontend-cluster-context"
./deploy-multi-cluster.sh
```

The script will:
1. Deploy backend cluster with your LLM configuration
2. Wait for LoadBalancer IPs to be assigned
3. Configure frontend with backend endpoints automatically
4. Deploy frontend cluster with your LLM configuration

## 3. Access URLs

Get service IPs and access the applications:
```bash
# Get service IPs
UI_IP=$(kubectl --context $FRONTEND_CONTEXT get svc -n lungo-frontend lungo-ui -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
LOGISTICS_IP=$(kubectl --context $FRONTEND_CONTEXT get svc -n lungo-frontend logistic-supervisor -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
GRAFANA_IP=$(kubectl --context $FRONTEND_CONTEXT get svc -n lungo-frontend lungo-frontend-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Lungo UI: http://$UI_IP:3000"
echo "Logistics API: http://$LOGISTICS_IP:9090"
echo "Grafana: http://$GRAFANA_IP:80 (admin/admin)"
```

## 4. Manual Deployment

### Backend Cluster
```bash
cd cluster-1-backend

# Add repositories
helm repo add external-secrets https://charts.external-secrets.io
helm repo add nats https://nats-io.github.io/k8s/helm/charts
helm repo add opentelemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# Deploy
helm dependency update .
helm --kube-context $BACKEND_CONTEXT install lungo-backend . \
  --create-namespace --namespace lungo-backend \
  --set nats.service.type=LoadBalancer \
  --set slim.service.type=LoadBalancer \
  --set clickhouse.service.type=LoadBalancer \
  --set opentelemetry-collector.service.type=LoadBalancer
```

### Frontend Cluster
```bash
cd cluster-2-frontend

# Get backend IPs
NATS_IP=$(kubectl --context $BACKEND_CONTEXT get svc -n lungo-backend lungo-backend-nats -o jsonpath='{.spec.clusterIP}')
SLIM_IP=$(kubectl --context $BACKEND_CONTEXT get svc -n lungo-backend lungo-backend-slim -o jsonpath='{.spec.clusterIP}')
OTEL_IP=$(kubectl --context $BACKEND_CONTEXT get svc -n lungo-backend lungo-backend-opentelemetry-collector -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
CLICKHOUSE_IP=$(kubectl --context $BACKEND_CONTEXT get svc -n lungo-backend lungo-backend-clickhouse -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Create backend endpoints configuration
cat > backend-endpoints.yaml <<EOF
transport:
  nats:
    endpoint: "nats://$NATS_IP:4222"
  slim:
    endpoint: "http://$SLIM_IP:46357"
observability:
  otlpEndpoint: "http://$OTEL_IP:4318"
grafana:
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
      - name: ClickHouse
        url: http://$CLICKHOUSE_IP:8123
EOF

# Deploy
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm dependency update .
helm --kube-context $FRONTEND_CONTEXT install lungo-frontend . \
  --create-namespace --namespace lungo-frontend \
  -f backend-endpoints.yaml
```

## 5. Troubleshooting

### Check Deployment Status
```bash
# Backend cluster
kubectl --context $BACKEND_CONTEXT get pods -n lungo-backend
kubectl --context $BACKEND_CONTEXT get services -n lungo-backend

# Frontend cluster  
kubectl --context $FRONTEND_CONTEXT get pods -n lungo-frontend
kubectl --context $FRONTEND_CONTEXT get services -n lungo-frontend
```

### Common Issues

**LoadBalancer IPs not assigned:**
```bash
# Check LoadBalancer support
kubectl --context $BACKEND_CONTEXT get nodes -o wide
```

**Cross-cluster connectivity issues:**
```bash
# Test network connectivity
kubectl --context $FRONTEND_CONTEXT run test-pod --image=busybox --rm -it -- wget -O- http://BACKEND_IP:4222
```

**LLM configuration not applied:**
```bash
# Check environment variables
kubectl --context $BACKEND_CONTEXT describe pod -n lungo-backend POD_NAME
kubectl --context $FRONTEND_CONTEXT describe pod -n lungo-frontend POD_NAME
```

**Services not starting:**
```bash
# Check logs
kubectl --context $BACKEND_CONTEXT logs -n lungo-backend POD_NAME
kubectl --context $FRONTEND_CONTEXT logs -n lungo-frontend POD_NAME
```

## 6. Manual LoadBalancer IP Updates

If you need to manually update the UI service endpoints after deployment:

### Option 1: Edit Generated Override Files (If deployed with script)
```bash
# The deployment script creates these files automatically
# You can edit them directly and reapply

# Edit backend endpoints
nano backend-endpoints.yaml

# Edit frontend LoadBalancer IPs
nano frontend-lb-config.yaml

# Then reapply the changes
helm --kube-context kind-lungo-frontend upgrade lungo-frontend . \
  --namespace lungo-frontend \
  -f backend-endpoints.yaml \
  -f frontend-lb-config.yaml
```

### Option 2: Using Custom Override File
```bash
# Create override file with new IPs
cat > custom-frontend-endpoints.yaml <<EOF
services:
  ui:
    config:
      exchangeAppApiUrl: "http://YOUR_EXCHANGE_IP:8000"
      logisticsAppApiUrl: "http://YOUR_LOGISTICS_IP:9090"
EOF

# Apply to frontend cluster
helm --kube-context kind-lungo-frontend upgrade lungo-frontend . \
  --namespace lungo-frontend -f custom-frontend-endpoints.yaml
```

### Option 3: Direct Helm Values
```bash
# Update frontend cluster with specific values
helm --kube-context kind-lungo-frontend upgrade lungo-frontend . \
  --namespace lungo-frontend \
  --set services.ui.config.exchangeAppApiUrl="http://YOUR_EXCHANGE_IP:8000" \
  --set services.ui.config.logisticsAppApiUrl="http://YOUR_LOGISTICS_IP:9090"
```

### Option 4: Get Current LoadBalancer IPs
```bash
# Check frontend cluster LoadBalancer IPs
kubectl --context kind-lungo-frontend get svc -n lungo-frontend | grep LoadBalancer

# Example output:
# lungo-exchange      LoadBalancer   10.96.6.70      172.18.201.1   8000:31282/TCP
# logistic-supervisor LoadBalancer  10.96.213.5     172.18.201.2   9090:31352/TCP
```

**Note:** The deployment script automatically configures these IPs, but you can override them manually if needed.

## 7. Production Considerations

### Security
- Use TLS for cross-cluster communication
- Implement network policies within clusters
- Use private LoadBalancers (internal-only)
- Rotate API keys regularly

### Networking
- Set up VPC peering (cloud) or VPN (hybrid)
- Configure DNS for service discovery
- Implement proper firewall rules between clusters

### Monitoring
- Configure centralized logging
- Set up alerts for service health
- Monitor cross-cluster latency

### Scaling
- Configure HPA for frontend services
- Scale backend infrastructure based on load
- Consider multi-region deployment for HA
