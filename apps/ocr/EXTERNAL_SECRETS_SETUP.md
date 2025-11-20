# 🔐 External Secrets Setup Guide

## 📋 **Overview**

External Secrets automatically syncs secrets from AWS Secrets Manager into Kubernetes Secrets. This setup includes:

1. **SecretStore** - Defines how to connect to AWS
2. **ServiceAccount** - Kubernetes identity with AWS permissions
3. **IAM Role** - AWS permissions for accessing secrets
4. **ExternalSecret** - Defines which secrets to sync

## 🏗️ **Architecture**

```
AWS Secrets Manager                    Kubernetes
┌─────────────────────────┐         ┌─────────────────────────┐
│ S3_KEYS-ZcLvPd          │         │ SecretStore             │
│ ├── ACCESS_KEY          │◄────────┤ - Region: eu-central-1  │
│ └── SECRET_KEY          │         │ - ServiceAccount        │
│                         │         └─────────────────────────┘
│ dev_kinesis_credentials │                    │
│ ├── key                 │                    │
│ ├── secret              │                    │
│ ├── kinesis_stream      │                    │
│ ├── region              │                    │
│ └── identity_pool_id    │                    │
│                         │                    │
│ OCR_AUTH_V3_DEV-wGolsn  │                    │
│ ├── AUTH_CLIENT_ID      │                    │
│ └── AUTH_CLIENT_SECRET  │                    │
│                         │                    │
│ OCR_JWT_SECRET_KEY      │                    │
└─────────────────────────┘                    │
                                               │
                                               ▼
                                    ┌─────────────────────────┐
                                    │ ExternalSecret          │
                                    │ - References SecretStore│
                                    │ - Lists secrets to sync │
                                    └─────────────────────────┘
                                               │
                                               ▼
                                    ┌─────────────────────────┐
                                    │ Kubernetes Secret       │
                                    │ ocr-secrets             │
                                    │ (Auto-generated)        │
                                    └─────────────────────────┘
                                               │
                                               ▼
                                    ┌─────────────────────────┐
                                    │ OCR Pod                 │
                                    │ - Uses ocr-secrets      │
                                    └─────────────────────────┘
```

## 🔧 **Setup Steps**

### **Step 1: Install External Secrets Operator**

```bash
# Add the Helm repository
helm repo add external-secrets https://charts.external-secrets.io

# Install the operator
helm install external-secrets \
  external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace
```

### **Step 2: Create IAM Policy**

```bash
# Create the IAM policy for accessing secrets
aws iam create-policy \
  --policy-name ExternalSecretsPolicy \
  --policy-document file://external-secrets-iam-policy.json
```

### **Step 3: Create IAM Role**

```bash
# Get your OIDC provider ID
OIDC_ID=$(aws eks describe-cluster --name your-cluster-name --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)

# Create trust policy
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::495947449196:oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/${OIDC_ID}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.eu-central-1.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:external-secrets:external-secrets-sa"
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

# Attach the policy
aws iam attach-role-policy \
  --role-name external-secrets-role \
  --policy-arn arn:aws:iam::495947449196:policy/ExternalSecretsPolicy
```

### **Step 4: Deploy Kubernetes Resources**

```bash
# Deploy the OCR service with External Secrets
kubectl apply -k overlays/dev
```

## 📁 **File Structure**

```
ocr/
├── base/
│   ├── secretstore.yaml              # AWS connection config
│   ├── external-secrets-sa.yaml      # ServiceAccount with IAM role
│   ├── external-secret.yaml          # Base secret sync config
│   └── external-secrets-iam-policy.json # IAM policy document
└── overlays/
    ├── dev/
    │   └── external-secret-patch.yaml # Dev-specific secrets
    └── qa/
        └── external-secret-patch.yaml # QA-specific secrets
```

## 🔍 **Key Components Explained**

### **1. SecretStore (`secretstore.yaml`)**
```yaml
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
          name: external-secrets-sa           # ServiceAccount with IAM role
          namespace: external-secrets
```

**Purpose**: Defines how to connect to AWS Secrets Manager
- **Region**: Specifies AWS region (`eu-central-1`)
- **ServiceAccount**: References the ServiceAccount with IAM permissions
- **Service**: Specifies AWS Secrets Manager service

### **2. ServiceAccount (`external-secrets-sa.yaml`)**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets-sa
  namespace: external-secrets
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::495947449196:role/external-secrets-role
```

**Purpose**: Kubernetes identity that can assume AWS IAM role
- **IAM Role**: `external-secrets-role` with Secrets Manager permissions
- **Namespace**: `external-secrets` (where the operator runs)

### **3. ExternalSecret (`external-secret.yaml`)**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ocr-external-secret
spec:
  secretStoreRef:
    name: aws-secrets-manager    # References SecretStore
  target:
    name: ocr-secrets           # Creates this Kubernetes Secret
  data:
  - secretKey: AWS_ACCESS_KEY_ID
    remoteRef:
      key: S3_KEYS-ZcLvPd       # AWS Secret name (no ARN needed)
      property: ACCESS_KEY      # Property within the secret
```

**Purpose**: Defines which secrets to sync from AWS
- **SecretStoreRef**: Points to the SecretStore configuration
- **Target**: Name of the Kubernetes Secret to create
- **RemoteRef**: AWS Secret name and property to sync

## 🚨 **Important Notes**

### **1. No ARNs in ExternalSecret**
The ExternalSecret uses **secret names only**, not full ARNs:
```yaml
# ✅ Correct - Just the secret name
remoteRef:
  key: S3_KEYS-ZcLvPd

# ❌ Wrong - Don't use full ARN
remoteRef:
  key: arn:aws:secretsmanager:eu-central-1:495947449196:secret:S3_KEYS-ZcLvPd
```

### **2. Region is in SecretStore**
The AWS region is specified in the SecretStore, not in ExternalSecret:
```yaml
# ✅ Correct - Region in SecretStore
spec:
  provider:
    aws:
      region: eu-central-1

# ❌ Wrong - Don't specify region in ExternalSecret
```

### **3. Account ID is in IAM Role**
The AWS account ID (`495947449196`) is specified in the IAM role ARN, not in the ExternalSecret.

## 🔍 **Verification Commands**

```bash
# Check if External Secrets operator is running
kubectl get pods -n external-secrets

# Check SecretStore status
kubectl get secretstore aws-secrets-manager -o yaml

# Check ExternalSecret status
kubectl get externalsecret ocr-external-secret
kubectl describe externalsecret ocr-external-secret

# Check generated Kubernetes Secret
kubectl get secret ocr-secrets -o yaml

# Check ServiceAccount
kubectl describe serviceaccount external-secrets-sa -n external-secrets

# Test AWS permissions
kubectl run test-pod --image=amazon/aws-cli --rm -it --restart=Never -- \
  aws secretsmanager describe-secret --secret-id S3_KEYS-ZcLvPd --region eu-central-1
```

## 🚨 **Troubleshooting**

### **Common Issues:**

1. **IAM Role Not Found**
   ```bash
   # Check if role exists
   aws iam get-role --role-name external-secrets-role
   ```

2. **Permission Denied**
   ```bash
   # Check IAM policy
   aws iam get-policy --policy-arn arn:aws:iam::495947449196:policy/ExternalSecretsPolicy
   ```

3. **Secret Not Found**
   ```bash
   # Check if secret exists in AWS
   aws secretsmanager describe-secret --secret-id S3_KEYS-ZcLvPd --region eu-central-1
   ```

4. **External Secrets Operator Not Running**
   ```bash
   # Check operator status
   kubectl get pods -n external-secrets
   kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
   ```
