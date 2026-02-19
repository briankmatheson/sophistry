#!/bin/sh

cluster=e73


# certmanager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.2/cert-manager.yaml

# rdbms op
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm upgrade --install cnpg \
  --namespace cnpg-system \
  --create-namespace \
  cnpg/cloudnative-pg

# standard sc
kubectl apply -f -<<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
allowedTopologies:
- matchLabelExpressions:
  - key: eks.amazonaws.com/compute-type
    values:
    - auto
provisioner: ebs.csi.eks.amazonaws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
  encrypted: "true"
EOF

# api gateway
helm install emissary-crds \
 --namespace emissary --create-namespace \
 oci://ghcr.io/emissary-ingress/emissary-crds-chart --version=3.10.0 \
 --set enableLegacyVersions=false \
 --set service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"=internet-facing \
 --wait
#helm install emissary  --namespace emissary  oci://ghcr.io/emissary-ingress/emissary-ingress --version=3.10.0  --set waitForApiext.enabled=false   --set service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"=internet-facing 

# lbaas
#curl https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/download/v2.14.1/v2_14_1_full.yaml | sed s/your-cluster-name/$cluster/g | kubectl apply -f -


#curl https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json| aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file:///dev/stdin
# eksctl create iamserviceaccount \
#     --cluster=$cluster \
#     --namespace=kube-system \
#     --name=aws-load-balancer-controller \
#     --attach-policy-arn=arn:aws:iam::531572984815:policy/AWSLoadBalancerControllerIAMPolicy \
#     --override-existing-serviceaccounts \
#     --region <aws-region-code> \
#     --approve


#helm upgrade aws-load-balancer-controller https://aws.github.io/eks-charts/aws-load-balancer-controller --install
# helm install aws-load-balancer-controller https://aws.github.com/eks-charts/aws-load-balancer-controller \
#   -n kube-system \
#   --set clusterName=$cluster \
#   --set serviceAccount.create=false \
#   --set serviceAccount.name=aws-load-balancer-controller \
#   --version 1.14.0

#kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml

