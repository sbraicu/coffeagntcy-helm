# Lungo Coffee Agency - Single Cluster with Dual LLM Configuration

This Helm chart deploys the Lungo Coffee Agency application on a single Kubernetes cluster with separate LLM configurations for frontend and backend services.

## Overview

This deployment option provides:
- **Single cluster deployment** - All services run in one Kubernetes cluster
- **Dual LLM configuration** - Separate LLM settings for frontend and backend services
- **Service separation** - Frontend services use one LLM configuration, backend services use another

## Service Classification

### Frontend Services (use `llm.frontend` config)
- `lungo-exchange` - Main exchange service
- `lungo-ui` - User interface

### Backend Services (use `llm.backend` config)
- All logistics services (`logistic-supervisor`, `logistic-farm`, `logistic-helpdesk`, `logistic-shipper`, `logistic-accountant`)
- All farm agents (`brazil-farm`, `colombia-farm`, `vietnam-farm`)
- MCP server (`weather-mcp-server`)

## Configuration

### LLM Settings

Configure separate LLM endpoints in `values.yaml`:

```yaml
llm:
  frontend:
    model: "azure/gpt-4o"
    apiKey: "your-frontend-api-key"
    apiBase: "https://your-frontend-azure-openai.openai.azure.com/"
    apiVersion: "2024-02-15-preview"
    temperature: 0.7
  backend:
    model: "azure/gpt-4o"
    apiKey: "your-backend-api-key"
    apiBase: "https://your-backend-azure-openai.openai.azure.com/"
    apiVersion: "2024-02-15-preview"
    temperature: 0.5
```

### External Secrets (Production)

For production deployments, use external secrets:

```yaml
externalSecrets:
  secretStoreName: "your-secret-store"
  secretStoreKind: "SecretStore"
  frontend:
    data:
      - secretKey: "llm-api-key"
        remoteRef:
          key: "lungo/frontend-llm-key"
          property: "api-key"
  backend:
    data:
      - secretKey: "llm-api-key"
        remoteRef:
          key: "lungo/backend-llm-key"
          property: "api-key"
```

## Deployment

1. Update the LLM configuration in `values.yaml`
2. Deploy the chart:

```bash
helm install lungo-dual-llm . -f values.yaml
```

## Use Cases

This configuration is ideal when you need:
- Different LLM models or endpoints for different service types
- Separate billing/quota management for frontend vs backend services
- Different temperature settings for user-facing vs internal services
- Compliance requirements that separate customer-facing and internal AI usage
