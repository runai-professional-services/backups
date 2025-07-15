#!/bin/bash

# Exit on error
set -e

# Print error message and exit
error_exit() {
  red_text "Error: $1" >&2
  exit 1
}


# Print success message in green color
green_text() {
  echo -e "\033[32m$1\033[0m"
}


# Print error message in red color
red_text() {
  echo -e "\033[31m$1\033[0m"
}


# Print warning message in yellow color
yellow_text() {
  echo -e "\033[33m$1\033[0m"
}


# Check if cli tools are installed
prerequisites() {
    echo "Checking prerequisites..."

    # Check if velero is installed
    if command -v velero >/dev/null 2>&1 && [ -x "$(command -v velero)" ]; then
      green_text "velero is installed and executable"
    else
      error_exit "velero is not installed or not executable. Please install velero cli tool."
    fi

    # Check if kubectl is installed
    if command -v kubectl >/dev/null 2>&1 && [ -x "$(command -v kubectl)" ]; then
      green_text "kubectl is installed and executable"
    else
      error_exit "kubectl is not installed or not executable. Please install the kubectl cli tool."
    fi

    # Check if helm is installed
    if command -v helm >/dev/null 2>&1 && [ -x "$(command -v helm)" ]; then
      green_text "helm is installed and executable"
    else
      error_exit "Helm is not installed. Do you want to install it? (y/n)"
      read -rp "Enter your choice: " INSTALL_HELM
      if [ "$INSTALL_HELM" == "y" ]; then
        install_helm
      else
        error_exit "Helm is required to install Min.io Operator. Please install it manually."
      fi
    fi
}


# Install Helm
install_helm() {
  green_text "Installing Helm..."
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod 700 get_helm.sh
  ./get_helm.sh
}


# Check if Min.io Operator is installed
check_minio_operator_installed() {
  if helm list -n minio-operator | grep -q "minio-operator"; then
    green_text "Min.io Operator is installed"
    MINIO_OPERATOR_INSTALLED="true"
  else
    yellow_text "Min.io Operator is not installed"
    MINIO_OPERATOR_INSTALLED="false"
  fi
}


# Install Min.io Operator
install_minio_operator() {
  check_minio_operator_installed
  if [ "$MINIO_OPERATOR_INSTALLED" == "false" ]; then
    green_text "Installing Min.io Operator..."
    helm repo add minio-operator https://operator.min.io
    helm repo update
    helm upgrade -i minio-operator -n minio-operator minio-operator/operator \
    --create-namespace
  fi  
}


# Create Min.io Tenant values file
create_minio_tenant_values_file() {
  green_text "Creating Min.io Tenant values file..."
  read -rp "Enter your Min.io Tenant domain name (e.g., example.com): " MINIO_DOMAIN
  read -rp "Enter the storage volume size in Gi (default: 20): " STORAGE_VOLUME_SIZE 
  STORAGE_VOLUME_SIZE=${STORAGE_VOLUME_SIZE:-20}
  read -rp "Enter the number of Min.io servers: (default: 1) " SERVER_COUNT
  SERVER_COUNT=${SERVER_COUNT:-1}
  read -rp "Enter the ingress class name: (default: nginx) " INGRESS_CLASS_NAME
  INGRESS_CLASS_NAME=${INGRESS_CLASS_NAME:-nginx}
    
  read -rp "Do you have a TLS certificate for your Mini.io domain? (y/n): " TLS_CERT_EXISTS
  if [ "$TLS_CERT_EXISTS" == "y" ]; then
    echo "Please create a secret for the Min.io Console and API Ingress."
    echo "Min.io Documentation: https://min.io/docs/minio/kubernetes/upstream/operations/network-encryption.html"
    read -rp "Enter the TLS certificate secret name for the Min.io API: " TLS_CERT_SECRET_NAME
    read -rp "Enter the TLS certificate secret name for the Min.io Console: " TLS_CERT_SECRET_NAME_CONSOLE
  else
    TLS_CERT_SECRET_NAME=""
    TLS_CERT_SECRET_NAME_CONSOLE=""
  fi

cat <<EOF > minio-tenant-values.yaml
tenant:
  name: minio
  configSecret:
    name: myminio-env-configuration
    accessKey: minio
    secretKey: minio123
  pools:
    - servers: ${SERVER_COUNT}
      volumesPerServer: 1
      name: pool-0
      size: ${STORAGE_VOLUME_SIZE}Gi
ingress:
  api:
    enabled: true
    ingressClassName: ${INGRESS_CLASS_NAME}
    host: minio.${MINIO_DOMAIN}
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
      nginx.ingress.kubernetes.io/proxy-body-size: 10G
EOF

  if [ -n "$TLS_CERT_SECRET_NAME" ]; then
  cat <<EOF >> minio-tenant-values.yaml
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
    tls:
      - hosts:
          - minio.${MINIO_DOMAIN}
        secretName: ${TLS_CERT_SECRET_NAME}
EOF
  fi

  cat <<EOF >> minio-tenant-values.yaml
  console:
    enabled: true
    ingressClassName: ${INGRESS_CLASS_NAME}
    host: minio-console.${MINIO_DOMAIN}
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
EOF

  if [ -n "$TLS_CERT_SECRET_NAME_CONSOLE" ]; then
    cat <<EOF >> minio-tenant-values.yaml
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
    tls:
      - hosts:
          - minio-console.${MINIO_DOMAIN}
        secretName: ${TLS_CERT_SECRET_NAME_CONSOLE}
EOF
  fi
}


# Check if Min.io Tenant is installed
check_minio_tenant_installed() {
  green_text "Checking if Min.io Tenant is installed..."
  if helm list -n minio-tenant | grep -q "minio-tenant"; then
    green_text "Min.io Tenant is installed"
    MINIO_TENANT_INSTALLED="true"
  else
    yellow_text "Min.io Tenant is not installed"
    MINIO_TENANT_INSTALLED="false"
  fi
}


# Install Min.io Tenant
install_minio_tenant() {
  check_minio_tenant_installed
  if [ "$MINIO_TENANT_INSTALLED" == "false" ]; then
  green_text "Installing the Min.io Tenant..."
  read -rp "Enter the namespace for the Min.io Tenant (default: minio-tenant): " MINIO_TENANT_NAMESPACE
  MINIO_TENANT_NAMESPACE=${MINIO_TENANT_NAMESPACE:-minio-tenant}

  helm upgrade -i minio-tenant -n ${MINIO_TENANT_NAMESPACE} minio-operator/tenant \
  -f minio-tenant-values.yaml \
  --create-namespace
  fi
}


# Provide Min.io instructions
provide_minio_instructions() {
  green_text "Min.io instructions..."
  echo "Min.io Console: https://minio-console.${MINIO_DOMAIN}"
  echo "Min.io API: https://minio.${MINIO_DOMAIN}"
  echo "Please use the Min.io Console to create an access key and a bucket."
  green_text "Min.io Documentation: https://min.io/docs/minio/kubernetes/upstream/administration/identity-access-management/minio-user-management.html#access-keys"
}


# Install Velero
install_velero() {
  green_text "Installing Velero..."
  read -rp "Enter the Min.io bucket name (default: backups): " VELERO_BUCKET
  VELERO_BUCKET=${VELERO_BUCKET:-backups}
  read -rp "Enter the Velero namespace (default: velero): " VELERO_NAMESPACE
  VELERO_NAMESPACE=${VELERO_NAMESPACE:-velero}

  velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.12.0 \
    --features=EnableCSI \
    --bucket ${VELERO_BUCKET} \
    --no-secret \
    --namespace ${VELERO_NAMESPACE}
}


# Create secret for bucket access
create_secret_for_bucket_access() {
  green_text "Creating secret for bucket access..."
  green_text "Please create an access key for the Min.io bucket."
  green_text "Min.io Documentation: https://min.io/docs/minio/kubernetes/upstream/administration/identity-access-management/minio-user-management.html#access-keys"
  read -rp "Enter the Minio access key: " AWS_ACCESS_KEY
  read -rp "Enter the Minio secret access key: " AWS_SECRET_ACCESS_KEY

  # Create credentials file
  cat <<EOF > credentials-velero
  [default]
  aws_access_key_id = ${AWS_ACCESS_KEY}
  aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
EOF

  # Create secret
  kubectl create secret generic -n velero minio-credentials \
    --from-file=cloud=credentials-velero
}


# Create Velero backup location
create_velero_backup_location() {
  local location_name="minio"
  local status=""

  green_text "Creating Velero backup location..."
  velero backup-location create minio --bucket ${VELERO_BUCKET} \
    --credential minio-credentials=cloud --provider aws \
    --config region=minio,s3ForcePathStyle="true",s3Url=https://minio.${MINIO_DOMAIN}

  # Check status of the backup location
  green_text "Waiting for Velero backup location '${location_name}' to become Available..."

  while true; do
    # Get the status of the backup location
    status=$(kubectl get backupstoragelocation -n ${VELERO_NAMESPACE} ${location_name} -o jsonpath='{.status.phase}' 2>/dev/null)
    if [[ "$status" == "Available" ]]; then
      green_text "Velero backup location '${location_name}' is Available!"
      break
    fi
    echo "Current status: ${status:-Not found}. Retrying in 5 seconds..."
    sleep 5
  done
}


main() {
    prerequisites
    install_minio_operator
    create_minio_tenant_values_file
    install_minio_tenant
    provide_minio_instructions
    install_velero
    create_secret_for_bucket_access
    create_velero_backup_location
}

main