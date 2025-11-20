# 🎯 Kustomize & External Secrets Complete Guide

## 📚 **What is Kustomize?**

Kustomize is a **Kubernetes-native configuration management tool** that lets you customize Kubernetes manifests without templates. It's like having a "base" configuration and then "overlaying" environment-specific changes.

### **Why Kustomize?**
- ✅ **No templates** - Pure YAML
- ✅ **GitOps friendly** - Version controlled
- ✅ **Environment separation** - Clean dev/qa/prod
- ✅ **Reusable** - Base configuration shared across environments

## 🏗️ **Kustomize Architecture**

```
ocr/
├── base/                    # 🏗️ Foundation (Common for ALL environments)
│   ├── kustomization.yaml   # Main configuration file
│   ├── deployment.yaml      # Base deployment (2 replicas, basic config)
│   ├── service.yaml         # Service definition
│   ├── configmap.yaml       # Common configuration
│   ├── secret.yaml          # Secret template
│   └── external-secret.yaml # AWS Secrets Manager integration
└── overlays/               # 🎨 Environment-specific customizations
    ├── dev/                # Development environment
    │   ├── kustomization.yaml      # Dev-specific config
    │   ├── deployment-patch.yaml   # Override resources, volumes
    │   ├── configmap-patch.yaml    # Override AUTH_URL
    │   └── external-secret-patch.yaml # Dev-specific secrets
    └── qa/                 # QA environment
        ├── kustomization.yaml      # QA-specific config
        ├── deployment-patch.yaml   # Override resources
        ├── configmap-patch.yaml    # Override AUTH_URL
        └── external-secret-patch.yaml # QA-specific secrets
```

## 🔧 **How Kustomize Works - Step by Step**

### **Step 1: Base Configuration**
```yaml
# base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ocr
spec:
  replicas: 2                    # Default: 2 replicas
  template:
    spec:
      containers:
      - name: ocr
        image: ocr:latest        # Default: latest tag
        resources:
          limits:
            memory: "4Gi"        # Default: 4Gi memory
```

### **Step 2: Dev Overlay Configuration**
```yaml
# overlays/dev/kustomization.yaml
resources:
  - ../../base                   # Use base as foundation

images:
  - name: ocr:latest
    newTag: version_3.7.5_45447a1_121  # Override image tag

patches:
  - path: deployment-patch.yaml  # Apply custom changes
```

### **Step 3: Dev Patch**
```yaml
# overlays/dev/deployment-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ocr
spec:
  template:
    spec:
      containers:
      - name: ocr
        resources:
          limits:
            memory: "7Gi"        # Override: 7Gi for dev
```

### **Step 4: Final Result**
Kustomize combines base + overlay to create:
```yaml
# Final deployment (what gets applied)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ocr
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: ocr
        image: ocr:version_3.7.5_45447a1_121  # From overlay
        resources:
          limits:
            memory: "7Gi"                      # From patch
```

## 🔐 **External Secrets Explained**

### **What is External Secrets?**
External Secrets is a Kubernetes operator that automatically syncs secrets from external sources (like AWS Secrets Manager) into Kubernetes Secrets.

### **Why External Secrets?**
- ✅ **Security** - Secrets stay in AWS Secrets Manager
- ✅ **Automation** - No manual secret management
- ✅ **Audit** - Centralized secret access
- ✅ **Rotation** - Automatic secret updates

### **How External Secrets Works**

#### **1. AWS Secrets Manager (Source)**
```
arn:aws:secretsmanager:eu-central-1:495947449196:secret:S3_KEYS-ZcLvPd
├── ACCESS_KEY: "AKIA..."
└── SECRET_KEY: "wJalrXUtnFEMI..."

arn:aws:secretsmanager:eu-central-1:495947449196:secret:dev_kinesis_credentials-J64zai
├── key: "AKIA..."
├── secret: "wJalrXUtnFEMI..."
├── kinesis_stream: "dev-stream"
├── region: "eu-central-1"
└── identity_pool_id: "eu-central-1:pool-id"
```

#### **2. SecretStore (AWS Connection Configuration)**
```yaml
# secretstore.yaml - Defines HOW to connect to AWS
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: eu-central-1                    # Your AWS region
      auth:
        serviceAccount:
          name: external-secrets-sa           # ServiceAccount with AWS permissions
          namespace: external-secrets
```

#### **3. External Secret Configuration**
```yaml
# external-secret.yaml - Defines WHAT to sync
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ocr-external-secret
spec:
  secretStoreRef:
    name: aws-secrets-manager    # References the SecretStore above
  target:
    name: ocr-secrets           # Creates this Kubernetes Secret
  data:
  - secretKey: AWS_ACCESS_KEY_ID
    remoteRef:
      key: S3_KEYS-ZcLvPd       # AWS Secret name (no ARN needed)
      property: ACCESS_KEY      # Property within the secret
```

#### **4. Generated Kubernetes Secret**
```yaml
# Automatically created by External Secrets
apiVersion: v1
kind: Secret
metadata:
  name: ocr-secrets
type: Opaque
data:
  AWS_ACCESS_KEY_ID: "QUtJQS4uLg=="  # Base64 encoded
  AWS_SECRET_ACCESS_KEY: "d0phbHJYVXRuRkVNSS4uLg=="
```

#### **5. Used in Deployment**
```yaml
# deployment.yaml
spec:
  template:
    spec:
      containers:
      - name: ocr
        envFrom:
        - secretRef:
            name: ocr-secrets  # References the generated secret
```

## 🚀 **Environment-Specific Secrets**

### **Dev Environment Secrets**
```yaml
# overlays/dev/external-secret-patch.yaml
# Dev doesn't need S3 keys (not in dev task definition)
spec:
  data:
  - secretKey: KINESIS_STREAM_NAME
    remoteRef:
      key: dev_kinesis_credentials-J64zai
      property: kinesis_stream
  - secretKey: AUTH_CLIENT_ID
    remoteRef:
      key: OCR_AUTH_V3_DEV-wGolsn
      property: AUTH_CLIENT_ID
  # ... other dev-specific secrets
```

### **QA Environment Secrets**
```yaml
# overlays/qa/external-secret-patch.yaml
# QA needs ALL secrets (matching qa task definition)
spec:
  data:
  - secretKey: AWS_ACCESS_KEY_ID
    remoteRef:
      key: S3_KEYS-ZcLvPd
      property: ACCESS_KEY
  - secretKey: AWS_SECRET_ACCESS_KEY
    remoteRef:
      key: S3_KEYS-ZcLvPd
      property: SECRET_KEY
  # ... all other secrets
```

## 🛠️ **Kustomize Commands**

### **Preview Changes**
```bash
# See what will be applied (dry run)
kubectl apply -k overlays/dev --dry-run=client

# See the final YAML that gets applied
kubectl kustomize overlays/dev

# Compare with current state
kubectl diff -k overlays/dev
```

### **Apply Changes**
```bash
# Deploy to development
kubectl apply -k overlays/dev

# Deploy to QA
kubectl apply -k overlays/qa

# Delete deployment
kubectl delete -k overlays/dev
```

### **Debug Commands**
```bash
# Check what resources exist
kubectl get all -l app=ocr

# Check external secrets status
kubectl get externalsecrets
kubectl describe externalsecret ocr-external-secret

# Check generated secrets
kubectl get secrets ocr-secrets -o yaml
```

## 📊 **ECS to EKS Migration Mapping**

| ECS Component | Kubernetes Equivalent | Kustomize Location |
|---------------|----------------------|-------------------|
| `cpu: 2048` | `cpu: "2048m"` | `base/deployment.yaml` |
| `memory: 7168` | `memory: "7Gi"` | `overlays/dev/deployment-patch.yaml` |
| `portMappings` | `ports` | `base/deployment.yaml` |
| `environment` | `env` + `configMap` | `base/configmap.yaml` |
| `secrets` | `envFrom` + `external-secret` | `base/external-secret.yaml` |
| `volumes` | `volumeMounts` + `volumes` | `overlays/dev/deployment-patch.yaml` |
| `logConfiguration` | `logConfiguration` | `base/deployment.yaml` |

## 🔍 **Key Differences Between Environments**

### **Dev Environment**
- **Image**: `version_3.7.5_45447a1_121`
- **Memory**: 7Gi (matching ECS dev)
- **AUTH_URL**: `https://authorization.dev-eks.internal-services:5800`
- **SSL Cert**: Host path mounting
- **Secrets**: No S3 keys needed

### **QA Environment**
- **Image**: `version_3.7.0_d75badd_9`
- **Memory**: 4Gi (matching ECS qa)
- **AUTH_URL**: `http://authorization.dev.local.dev:5800`
- **SSL Cert**: No host path mounting
- **Secrets**: All secrets including S3 keys

## 🔐 **IAM Setup for External Secrets**

### **Required AWS IAM Role and Policy**

You need to create an IAM role that External Secrets can use to access AWS Secrets Manager:

#### **1. Create IAM Policy**
```bash
# Create the policy using the provided JSON
aws iam create-policy \
  --policy-name ExternalSecretsPolicy \
  --policy-document file://external-secrets-iam-policy.json
```

#### **2. Create IAM Role**
```bash
# Create trust policy for EKS
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::495947449196:oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.eu-central-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE:sub": "system:serviceaccount:external-secrets:external-secrets-sa"
        }
      }
    }
  ]
}
EOF

# Create the role
aws iam create-role \
  --role-name external-secrets-role \
  --assume-role-policy-document file://trust-policy.json

# Attach the policy to the role
aws iam attach-role-policy \
  --role-name external-secrets-role \
  --policy-arn arn:aws:iam::495947449196:policy/ExternalSecretsPolicy
```

#### **3. Update OIDC Provider**
Replace `EXAMPLED539D4633E53DE1B71EXAMPLE` with your actual OIDC provider ID:
```bash
# Get your OIDC provider ID
aws eks describe-cluster --name your-cluster-name --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5
```

## 🚨 **Common Issues & Solutions**

### **1. External Secrets Not Working**
```bash
# Check if external-secrets operator is installed
kubectl get pods -n external-secrets

# Check secret store configuration
kubectl get secretstore aws-secrets-manager -o yaml

# Check external secret status
kubectl describe externalsecret ocr-external-secret

# Check IAM role permissions
kubectl describe serviceaccount external-secrets-sa -n external-secrets
```

### **2. Image Pull Errors**
```bash
# Check ECR permissions
kubectl describe pod <pod-name>

# Verify image exists
aws ecr describe-images --repository-name ocr --image-ids imageTag=version_3.7.5_45447a1_121
```

### **3. Resource Limits**
```bash
# Check resource usage
kubectl top pods -l app=ocr

# Check HPA status
kubectl get hpa ocr-hpa
```

## 📝 **Best Practices**

1. **Base Configuration**: Keep common settings in base
2. **Environment Separation**: Use overlays for environment-specific changes
3. **Secret Management**: Use External Secrets for AWS integration
4. **Resource Limits**: Set appropriate requests/limits
5. **Health Checks**: Always include liveness/readiness probes
6. **Security**: Use NetworkPolicy and ServiceAccount
7. **Monitoring**: Include proper labels and annotations
