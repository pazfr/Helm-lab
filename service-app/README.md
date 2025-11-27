# ArgoCD ApplicationSets for Service Deployment

This directory contains ArgoCD ApplicationSets for managing service deployments across multiple environments.

## Structure

```
service-app/
├── applicationset/
│   ├── services-matrix-applicationset.yaml    # Matrix generator for services
│   ├── companies-helm-applicationset.yaml     # Helm-based companies (per-company values)
│   └── services-helm-applicationset.yaml      # Helm-based services & shared infra (per-service chart and shared-infra chart)
├── kustomization.yaml                         # Kustomize configuration
└── README.md                                  # This file
```

## ApplicationSets

### 1. Services Matrix ApplicationSet

**File**: `applicationset/services-matrix-applicationset.yaml`

This ApplicationSet uses a matrix generator to create applications for multiple services across multiple environments.

**Services**: ocr, service-b through service-p (16 total services)
**Environments**: dev, qa, staging, production

**Generated Applications**:
- `ocr-dev`, `ocr-qa`, `ocr-staging`, `ocr-production`
- `service-b-dev`, `service-b-qa`, `service-b-staging`, `service-b-production`
- ... and so on for all services

### 2. Helm Services & Shared Infra ApplicationSet

**File**: `applicationset/services-helm-applicationset.yaml`

This ApplicationSet deploys both per-service Helm releases and the shared infrastructure (namespaces + shared-config ConfigMap). The shared-infra release uses `helm/charts/shared-infra` with env-specific values (`helm/values/envs/<env>.shared-config.yaml`).

**Generated Applications** (current env list):
- `shared-infra-dev`, `shared-infra-qa`

### 3. Helm Companies ApplicationSet

**File**: `applicationset/companies-helm-applicationset.yaml`

This ApplicationSet deploys per-company instances of the `companies` service and related services (console, client-onboarding, portal) via the shared service chart. Companies are sourced from `service-app/config/companies.yaml`; value files include service/env defaults plus optional company overrides (`helm/values/services/<svc>-<company>-<env>.yaml`). Hosts are templated as `<env>-eks-<company>-<svc>.purpleray.com`, and service names are suffixed with the company to avoid collisions.

## Repository Configuration

**Repository**: https://bitbucket.org/scanovate/eks-argocd-deployment.git
**Branch**: main

## Usage

### Deploy ApplicationSets

```bash
# Deploy all ApplicationSets
kubectl apply -k eks-argocd-deployment/service-app/

# Deploy specific ApplicationSet
kubectl apply -f eks-argocd-deployment/service-app/applicationset/services-matrix-applicationset.yaml
```

### View Generated Applications

```bash
# List all applications
kubectl get applications -n argocd

# List applications by label
kubectl get applications -n argocd -l app=ocr
kubectl get applications -n argocd -l environment=dev
```

### Delete Applications

```bash
# Delete all applications
kubectl delete -k eks-argocd-deployment/service-app/

# Delete specific ApplicationSet
kubectl delete -f eks-argocd-deployment/service-app/applicationset/services-matrix-applicationset.yaml
```

## Service Directory Structure

Each service should have the following directory structure in your Bitbucket repository:

```
app/
├── ocr/
│   ├── base/
│   └── overlays/
│       ├── dev/
│       ├── qa/
│       ├── staging/
│       └── production/
├── service-b/
│   ├── base/
│   └── overlays/
│       ├── dev/
│       ├── qa/
│       ├── staging/
│       └── production/
└── ...
```

## Adding New Services

To add a new service, update the `services-matrix-applicationset.yaml`:

```yaml
- list:
    elements:
    - name: ocr
    - name: service-b
    # ... existing services ...
    - name: new-service  # Add your new service here
```

## Adding New Environments

To add a new environment, update both ApplicationSet files:

```yaml
- list:
    elements:
    - env: dev
    - env: qa
    - env: staging
    - env: production
    - env: new-env  # Add your new environment here
```

## Sync Policy

The ApplicationSets are configured with automated sync policies:

- **Automated**: Applications sync automatically when changes are detected
- **Prune**: Resources not in Git are automatically deleted
- **Self-heal**: Applications automatically sync when drift is detected

## Namespace Strategy

All services are deployed to the `app` namespace. The shared infrastructure creates the namespace if it doesn't exist.

## Labels and Annotations

All applications are labeled with:
- `app`: Service name
- `environment`: Environment name (dev, qa, staging, production)
- `managed-by`: argocd

## Troubleshooting

### Check Application Status

```bash
# Check application health
kubectl get applications -n argocd -o wide

# Check application events
kubectl describe application <app-name> -n argocd
```

### Check ApplicationSet Status

```bash
# Check ApplicationSet status
kubectl get applicationsets -n argocd

# Check ApplicationSet events
kubectl describe applicationset <name> -n argocd
```

### Sync Issues

If applications are not syncing:

1. Check if the Bitbucket repository is accessible
2. Verify the main branch exists
3. Check if the specified path exists in the repository
4. Verify ArgoCD has permissions to access the Bitbucket repository
