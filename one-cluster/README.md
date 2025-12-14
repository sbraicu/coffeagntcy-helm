# Lungo Single-Cluster Deployment

Deploy the complete Lungo application stack in a single Kubernetes cluster with LoadBalancer support.

## Architecture

This deployment includes all Lungo services in one cluster:
- **Exchange API** (LoadBalancer) - Coffee trading exchange
- **UI Service** (LoadBalancer) - Web interface  
- **Logistics Supervisor** (LoadBalancer) - Logistics management API
- **Farm Services** - Brazil, Colombia, Vietnam coffee farms (NATS transport)
- **Logistics Services** - Farm, Helpdesk, Shipper, Accountant (SLIM transport)
- **Infrastructure** - NATS, SLIM, ClickHouse, OpenTelemetry, Grafana
- **MCP Services** - Weather data provider

## Prerequisites

- Kubernetes cluster with LoadBalancer support
- Helm 3.x
- kubectl configured for your cluster

## Quick Start (Local Development)

### 1. One-Command Setup and Deploy
```bash
# Step 1: Create cluster and install MetalLB
./setup-local-cluster.sh

# Step 2: Deploy Lungo chart
./deploy-chart.sh
```

This single script will:
- Create kind cluster with LoadBalancer support
- Install and configure MetalLB
- Deploy the complete Lungo application
- Show access points when ready

### 2. Configure LLM Settings (Optional)
Before running the script, edit `values.yaml` to configure your LLM provider:

**Option A: Direct Configuration (Development)**
```yaml
llm:
  model: "gpt-4o"                                    # Your LLM model
  provider: "azure"                                  # azure, openai, local, etc.
  endpoint: "https://your-azure-openai.openai.azure.com/"  # LLM endpoint
  apiKey: "your-api-key-here"                        # API key (leave empty for local)
  temperature: 0.7                                   # Response creativity (0.0-1.0)
```

**Option B: External Secrets (Production)**
For production deployments, use External Secrets to manage API keys securely:

```yaml
# Enable external secrets
externalSecrets:
  secretStoreName: "aws-secrets-manager"             # Your secret store
  secretStoreKind: "SecretStore"                     # SecretStore or ClusterSecretStore
  data:
    - secretKey: "llm-api-key"                       # Key in Kubernetes secret
      remoteRef:
        key: "lungo/llm-api-key"                     # Key in external store
        property: "api-key"                          # Property within the key

llm:
  model: "gpt-4o"
  provider: "azure"
  endpoint: "https://your-azure-openai.openai.azure.com/"
  apiKey: ""                                         # Leave empty - will come from external secret
  temperature: 0.7
```

## Production Deployment

### 1. Configure LLM Provider
Update `values.yaml` with your production LLM settings:

**Azure OpenAI:**
```yaml
llm:
  model: "gpt-4o"
  provider: "azure"
  endpoint: "https://your-resource.openai.azure.com/"
  apiKey: "your-azure-api-key"
  temperature: 0.7
```

**OpenAI:**
```yaml
llm:
  model: "gpt-4"
  provider: "openai"
  endpoint: "https://api.openai.com/v1"
  apiKey: "sk-your-openai-key"
  temperature: 0.7
```

**Local/On-premises:**
```yaml
llm:
  model: "llama-2-7b"
  provider: "local"
  endpoint: "http://your-llm-server:8080"
  apiKey: ""
  temperature: 0.7
```

### 2. Deploy to Production Cluster
```bash
# Deploy with production values
helm install lungo . --create-namespace --namespace lungo

# Or upgrade existing deployment
helm upgrade lungo . --namespace lungo
```

### 3. Configure External Access
For production, consider using Ingress instead of LoadBalancer:

```yaml
# In values.yaml
serviceType: ClusterIP  # Change from LoadBalancer

# Then create Ingress resources for external access
```

## Configuration Options

### Service Types
```yaml
serviceType: LoadBalancer  # LoadBalancer, ClusterIP, NodePort
```

### LLM Configuration
Configure your LLM provider in `values.yaml`. Services receive provider-specific environment variables:

**Azure OpenAI:**
```yaml
llm:
  model: "azure/your-deployment-name"
  temperature: 0.7
  azure:
    apiKey: "your-azure-api-key"
    apiBase: "https://your-resource.openai.azure.com/"
    apiVersion: "2024-02-15-preview"
```

**OpenAI:**
```yaml
llm:
  model: "openai/gpt-4"
  temperature: 0.7
  openai:
    apiKey: "your-openai-api-key"
    temperature: 0.7
```

**GROQ:**
```yaml
llm:
  model: "groq/llama-3.1-70b-versatile"
  temperature: 0.7
  groq:
    apiKey: "your-groq-api-key"
```

### External Dependencies
The chart includes these external services:
- **ClickHouse** - Data storage
- **NATS** - Messaging for farm services
- **SLIM** - Transport for logistics services  
- **Grafana** - Monitoring dashboard
- **OpenTelemetry** - Observability collector

## Monitoring

Access Grafana dashboard:
```bash
# Get Grafana service
kubectl get svc -n lungo lungo-grafana

# Port forward if ClusterIP
kubectl port-forward -n lungo svc/lungo-grafana 3000:80

# Default credentials: admin/admin
```

## External Secrets (Production)

For production deployments, External Secrets Operator can integrate with your existing secret management infrastructure.

### Prerequisites
- Existing secret management system (HashiCorp Vault, AWS Secrets Manager, Azure Key Vault, etc.)
- External Secrets Operator installed in your cluster
- SecretStore configured for your secret management system

### Setup Steps

1. **Store your API key in your existing secret management system**

2. **Ensure you have a SecretStore configured** (example for Vault):
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: lungo
spec:
  provider:
    vault:
      server: "https://your-vault-server:8200"
      path: "secret"
      version: "v2"
      auth:
        tokenSecretRef:
          name: vault-credentials
          key: token
```

3. **Uncomment and configure externalSecrets in values.yaml**:
```yaml
externalSecrets:
  secretStoreName: "vault-backend"
  secretStoreKind: "SecretStore"
  data:
    - secretKey: "llm-api-key"
      remoteRef:
        key: "lungo/llm-api-key"
        property: "api-key"
```

4. **Deploy with External Secrets enabled**:
```bash
helm upgrade lungo . --namespace lungo
```

The LLM_API_KEY will now be sourced from your external secret store instead of values.yaml.

The LLM_API_KEY will now be sourced from your external secret store instead of values.yaml.

## Troubleshooting

### Check Pod Status
```bash
kubectl get pods -n lungo
kubectl describe pod <pod-name> -n lungo
```

### Check LLM Configuration
```bash
# Verify LLM environment variables
kubectl exec -n lungo deployment/logistic-supervisor -- env | grep LLM
```

### Check Services
```bash
# Verify LoadBalancer IPs assigned
kubectl get svc -n lungo | grep LoadBalancer
```

### Check Logs
```bash
kubectl logs -n lungo deployment/lungo-exchange
kubectl logs -n lungo deployment/logistic-supervisor
```

## Manual LoadBalancer IP Updates

If you need to manually update the UI service endpoints after deployment:

### Option 1: Edit Generated Override File (If deployed with script)
```bash
# The deployment script creates this file automatically
# You can edit it directly and reapply
nano loadbalancer-ips.yaml

# Then reapply the changes
helm upgrade lungo . --namespace lungo -f loadbalancer-ips.yaml
```

### Option 2: Using Custom Override File
```bash
# Create override file with new IPs
cat > custom-endpoints.yaml <<EOF
services:
  ui:
    config:
      exchangeAppApiUrl: "http://YOUR_EXCHANGE_IP:8000"
      logisticsAppApiUrl: "http://YOUR_LOGISTICS_IP:9090"
EOF

# Apply the changes
helm upgrade lungo . --namespace lungo -f custom-endpoints.yaml
```

### Option 3: Direct Helm Values
```bash
# Update with specific values
helm upgrade lungo . --namespace lungo \
  --set services.ui.config.exchangeAppApiUrl="http://YOUR_EXCHANGE_IP:8000" \
  --set services.ui.config.logisticsAppApiUrl="http://YOUR_LOGISTICS_IP:9090"
```

### Option 4: Get Current LoadBalancer IPs
```bash
# Check current LoadBalancer IPs
kubectl get svc -n lungo | grep LoadBalancer

# Example output:
# lungo-exchange    LoadBalancer   10.96.6.70      172.18.255.1   8000:31282/TCP
# logistic-supervisor LoadBalancer 10.96.213.5     172.18.255.2   9090:31352/TCP
```

**Note:** The deployment script automatically configures these IPs, but you can override them manually if needed.

```bash
# Delete deployment
helm uninstall lungo --namespace lungo

# Delete namespace
kubectl delete namespace lungo

# Delete local cluster (if using kind)
kind delete cluster --name lungo
```

## Architecture Notes

- **Farm Services** use NATS for messaging
- **Logistics Services** use SLIM transport  
- **LoadBalancer** services get external IPs for direct access
- **LLM Configuration** is injected into all relevant services
- **Single Namespace** deployment for simplicity
- **External Dependencies** managed via Helm subcharts
