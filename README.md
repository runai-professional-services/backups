# Run:Ai Backups with Velero

Provides instructions and artifacts to deploy Velero to backup a Run:Ai environment. This includes additional 
instructions such as deploying Min.io to use as a backup target. 

## Table of Contents

- [Prerequisites](#prerequisites)
- [Manual Deployment](#manual-deployment)
  - [Install Min.io](#install-minio)
  - [Install Velero](#install-velero)
- [Backup Run:Ai](#how-to-backup-runai-with-velero)
- [Restore Run:Ai](#how-to-restore-runai-from-backups)
- [Upgrade Velero](#how-to-upgrade-velero)

## Prerequisites

1. Two TLS certificates for Min.io. You will need the TLS certfiicates for the Min.io console and the API service. Recommended naming convention for the certificates is:

    `minio.<your-domain>` 
    
    `minio-console.<your-domain>`

2. DNS entries for both Min.io domains, to provide external access from clients and Velero services.

3. Storage class to provision a `PVC` for Min.io.

4. Helm cli tool. 
    
    https://helm.sh/docs/intro/install/

5. Velero cli tool.

    https://velero.io/docs/v1.8/basic-install/#install-the-cli

6. Kubectl cli tool. 

    https://kubernetes.io/docs/tasks/tools/

## Manual Deployment

Follow the instructions to manually deploy Min.io and Velero to backup the Run:Ai environment.

## Install Min.io

> **Note:** Velero requires an S3 bucket as a backup destination. You can leverage Min.io an open source S3 provider if a cloud service is unavailable.

### Install the Min.io Operator

1. Deploy the Min.io operator with `Helm`. 

    ```bash
    helm repo add minio-operator https://operator.min.io
    helm repo update

    helm upgrade -i minio-operator -n minio-operator minio-operator/operator \
      --create-namespace
    ```

### Deploy a Min.io Tenant

1. Create a tenants value file. I have enabled access to Min.io through my nginx ingress deployment. You will need to update the host names to match your DNS entries.

    `tenant-values.yaml`

    ```bash
    tenant:
      name: minio
      configSecret:
        name: myminio-env-configuration
        accessKey: minio
        secretKey: minio123
      pools:
        - servers: 1
          volumesPerServer: 1
          name: pool-0
    ingress:
      api:
        enabled: true
        ingressClassName: "nginx"
        annotations:
          cert-manager.io/cluster-issuer: letsencrypt-prod
          nginx.ingress.kubernetes.io/ssl-redirect: "true"
          nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
          nginx.ingress.kubernetes.io/proxy-body-size: 10G
        tls:
          - hosts:
            - minio.<your-domain>
            secretName: minio-tls
        host: minio.<your-domain>
      console:
        enabled: true
        ingressClassName: "nginx"
        annotations:
          cert-manager.io/cluster-issuer: letsencrypt-prod
          nginx.ingress.kubernetes.io/ssl-redirect: "true"
          nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
        tls:
          - hosts:
            - minio-console.<your-domain>
            secretName: minio-console-tls
        host: minio-console.<your-domain>
    ```

2. Install the Min.io tenant with the following helm command.

    ```bash
    helm upgrade -i minio-tenant -n minio-tenant minio-operator/tenant \
      --create-namespace \
      -f tenant-values.yaml
    ```

### Create a Min.io bucket

1. Log into the minio-console. The default username and password are `minio/minio123`.
2. Create a new bucket called `backups`.
3. Click on access keys and create new credentials to access you backups bucket.

## Install Velero

1. The velero install can be done using the velero cli.

    ```bash
    brew install velero
    ```

2. Here is an example install when using Min.io as your backup target. 

    ```bash
    velero install \
      --provider aws \
      --plugins velero/velero-plugin-for-aws:v1.12.0 \
      --features=EnableCSI \
      --bucket backups \
      --no-secret \
      --namespace velero
    ```

3. Create a file named `credentials-velero`.

    ```bash
    [default]
    aws_access_key_id = xxxxxxxxxx # Key from credentials in minio
    aws_secret_access_key = xxxxxxxxxxxxxxxxxx # Key from credentials in minio
    ```

4. Create a new `backupStorageLocation`. Update the Min.io domain.

    ```bash
    kubectl create secret generic -n velero minio-credentials \
    --from-file=cloud=credentials-velero

    velero backup-location create minio --bucket backups \
    --credential minio-credentials=cloud --provider aws \
    --config region=minio,s3ForcePathStyle="true",s3Url=https://minio.<minio-domain>
    ```

5. Validate the `backupStorageLocation` is in an `Available` state.

    ```bash
    kubectl get backupstoragelocation -n velero | grep minio
    ```

### Install instructions when using AWS S3 instead of Min.io

1. Create an S3 bucket in AWS.

2. Give permissions to the bucket. You will need to update the `role` and the `bucket-name` Here is an example:

    ```bash
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "AWS": "arn:aws:iam::xxxx:role/brad-velero" #Update with approperiate role
                },
                "Action": [
                    "s3:PutObject",
                    "s3:GetObject",
                    "s3:ListBucket",
                    "s3:DeleteObject",
                    "s3:GetBucketLocation",
                    "s3:ListMultipartUploadParts",
                    "s3:AbortMultipartUpload"
                ],
                "Resource": [
                    "arn:aws:s3:::<bucket-name>", #Update the bucket-name
                    "arn:aws:s3:::<bucket-name>/*" #Update the bucket-name
                ]
            }
        ]
     }
    ```

3. Install Velero, the backup location in my example is the region the S3 bucket resides.

    ```bash
    velero install \
      --provider aws \
      --plugins velero/velero-plugin-for-aws:v1.12.0 \
      --features=EnableCSI \
      --no-secret \
      --use-node-agent \
      --bucket brad-velero \
      --backup-location-config region=us-east-1 \
      --snapshot-location-config region=us-east-1 \
      --namespace velero
    ```

### Optional -  EKS Deployments additional Steps when using EBS volumes

1. If the cluster does not have the Snapshot Controller CRDs they need to be installed.

    ```bash
    kubectl kustomize https://github.com/kubernetes-csi/external-snapshotter/client/config/crd | kubectl create -f -
    ```

2. Make sure the snapshot location is set. This is required when using EBS volumes. You can do this with the velero cli. Update your region to match the location of the volumes.

    ```bash
    velero snapshot-location create ebs-snapshots \
      --provider aws \
      --config region=us-east-1 #Update to the region your ebs volumes reside
    ```

## How to Backup Run:Ai with Velero

1. Perform a backup on the `runai-backend`.

    ```bash
    velero backup create runai-backend --include-namespaces runai-backend \
      --volume-snapshot-locations ebs-snapshots \
      --storage-location minio
    ```

2. Describe the backup job to see the status.

    ```bash
    velero backup describe runai-backend
    ```

3. Grab the `runai` namespaces these will be used for additional backups.

    ```bash 
    RUNAI_NAMESPACES=$(kubectl get namespaces --no-headers -o custom-columns=":metadata.name" | grep '^runai' | grep -v runai-backend | tr '\n' ',' | sed 's/,$//')

    echo $RUNAI_NAMESPACES
    ```

4. Backup the CRDs in the cluster, these are needed for a full Run:Ai cluster restore.

    ```bash
    velero backup create runai-crds \
      --include-resources customresourcedefinitions.apiextensions.k8s.io,clusterrolebindings.rbac.authorization.k8s.io,clusterroles.rbac.authorization.k8s.io \
      --volume-snapshot-locations ebs-snapshots \
      --storage-location minio \
      --snapshot-volumes=false 
    ```

5. Run a backup for the runai namespaces.

    ```bash
    velero backup create runai \
      --include-namespaces $RUNAI_NAMESPACES \
      --volume-snapshot-locations ebs-snapshots \
      --storage-location minio
    ```

6. At this point you should have the 3 following backups: `runai-backend`, `runai-crds`, `runai`.

## How to Restore Run:Ai from Backups

1. Restore the 3 backups. This for example would re-deploy Run:ai on a new cluster.

    ```bash
    velero restore create restore-backend --from-backup runai-backend
    velero restore create restore-runai-crds --from-backup runai-crds
    velero restore create restore-cluster --from-backup runai
    ```

2. Following the restore, it’s always a good idea to perform a Helm upgrade. This is to ensure the Run:Ai cluster and control plane are in a healthy state. For example:

    ```bash
    helm get values runai-cluster -n runai > cluster-values.yaml

    helm upgrade runai-cluster -n runai runai/runai-cluster \
      --version=<runai-cluster-version> \
      -f cluster-values.yaml
    ```

## How to Upgrade Velero

1. Here is an example of upgrading Velero.

    ```bash
    kubectl set image deployment/velero \
    velero=velero/velero:v1.16.0 \
    velero-plugin-for-aws=velero/velero-plugin-for-aws:v1.12.0 \
    --namespace velero
    ```