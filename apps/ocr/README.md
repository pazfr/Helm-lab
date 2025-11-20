# OCR Service - Kubernetes Deployment

This directory contains the Kubernetes manifests for the OCR service using Kustomize for environment-specific configurations.

## Structure

```
ocr/
├── base/                    # Base configuration
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   ├── serviceaccount.yaml
│   ├── pdb.yaml
│   ├── ingress.yaml
│   ├── hpa.yaml
│   └── networkpolicy.yaml
└── overlays/               # Environment-specific configurations
    ├── dev/
    │   ├── kustomization.yaml
    │   ├── deployment-patch.yaml
    │   └── configmap-patch.yaml
    └── qa/
        ├── kustomization.yaml
        ├── deployment-patch.yaml
        └── configmap-patch.yaml
```

## Migration from ECS to EKS

This configuration migrates the OCR service from ECS to EKS with the following improvements:

### Key Changes:
- **Resource Management**: Converted ECS CPU/memory units to Kubernetes resource requests/limits
- **Secrets Management**: Moved from AWS Secrets Manager to Kubernetes Secrets (can be integrated with external-secrets)
- **Networking**: Added NetworkPolicy for security, Ingress for external access
- **Scaling**: Added HorizontalPodAutoscaler for automatic scaling
- **High Availability**: Added PodDisruptionBudget and proper replica management
- **Monitoring**: Added health checks and readiness probes

### Resource Mapping:
| ECS | Kubernetes |
|-----|------------|
| CPU: 2048 | CPU: 2048m (2 cores) |
| Memory: 4096MB/7168MB | Memory: 4Gi/7Gi |
| Port: 5040 | Port: 5040 |
| Environment Variables | ConfigMap + Secrets |

## Usage

### Deploy to Development Environment:
```bash
kubectl apply -k overlays/dev
```

### Deploy to QA Environment:
```bash
kubectl apply -k overlays/qa
```

### Preview Changes:
```bash
kubectl diff -k overlays/dev
```

## Configuration

### Base Configuration
- **Replicas**: 2 (minimum for HA)
- **Resources**: Configurable per environment
- **Health Checks**: Liveness and readiness probes
- **Security**: NetworkPolicy, ServiceAccount with IAM role

### Environment-Specific Overrides

#### Development
- **Image**: `version_3.7.5_45447a1_121`
- **Memory**: 7Gi (matching ECS dev configuration)
- **AUTH_URL**: `https://authorization.dev-eks.internal-services:5800`
- **SSL Cert**: Host path mounting for SSL certificates

#### QA
- **Image**: `version_3.7.0_d75badd_9`
- **Memory**: 4Gi (matching ECS qa configuration)
- **AUTH_URL**: `http://authorization.dev.local.dev:5800`

## Prerequisites

1. **EKS Cluster**: Must be running with proper IAM roles
2. **ECR Access**: ServiceAccount must have permissions to pull images
3. **Secrets**: AWS Secrets Manager integration (via external-secrets)
4. **Ingress Controller**: NGINX ingress controller installed
5. **Metrics Server**: For HPA functionality

## Security Considerations

- **NetworkPolicy**: Restricts traffic to/from the service
- **ServiceAccount**: Uses IAM roles for AWS service access
- **Secrets**: Sensitive data stored in Kubernetes secrets
- **TLS**: Ingress configured with SSL termination

## Monitoring

- **Health Checks**: `/health` and `/ready` endpoints
- **Metrics**: CPU and memory monitoring for HPA
- **Logging**: AWS CloudWatch integration via fluentd/fluent-bit

## Troubleshooting

### Common Issues:
1. **Image Pull Errors**: Check ECR permissions and image tags
2. **Resource Limits**: Monitor CPU/memory usage
3. **Network Connectivity**: Verify NetworkPolicy rules
4. **Secrets**: Ensure external-secrets is properly configured

### Commands:
```bash
# Check pod status
kubectl get pods -l app=ocr

# View logs
kubectl logs -l app=ocr

# Check events
kubectl get events --sort-by='.lastTimestamp'

# Test connectivity
kubectl exec -it <pod-name> -- curl localhost:5040/health
```
