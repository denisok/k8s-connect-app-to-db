#!/bin/bash

set -e

echo "########## starting minikube"

minikube start --nodes=4 --cpus=3 --memory=4G --kubernetes-version=1.23.15

echo
echo "########## installing correct storage"
# https://github.com/kubernetes/minikube/issues/12360

minikube addons disable storage-provisioner
kubectl delete storageclass standard
kubectl apply -f https://raw.githubusercontent.com/percona/dbaas-operator/main/dev/kubevirt-hostpath-provisioner.yaml

echo
echo "########## install OLM"

#operator-sdk olm install

kubectl create -f https://github.com/operator-framework/operator-lifecycle-manager/releases/latest/download/crds.yaml
kubectl wait --for=condition=Established -f https://github.com/operator-framework/operator-lifecycle-manager/releases/latest/download/crds.yaml

kubectl create -f https://github.com/operator-framework/operator-lifecycle-manager/releases/latest/download/olm.yaml

kubectl rollout status -w deployment/olm-operator --namespace=olm
kubectl rollout status -w deployment/catalog-operator --namespace=olm

sleep 10


echo
echo "########## operator group"

cat <<EOF | kubectl apply -f -
kind: OperatorGroup
apiVersion: operators.coreos.com/v1
metadata:
  name: og-single
  namespace: default
spec:
  targetNamespaces:
  - default
EOF

echo
echo "########## install Service Binding operator"

kubectl create -f https://operatorhub.io/install/service-binding-operator.yaml

echo
echo "########## install DBaaS catalog"

cat <<EOF | kubectl apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: dbaas-catalog
  namespace: olm
spec:
  displayName: DBaaS Platform Catalog
  publisher: DBaaS Community
  sourceType: grpc
  image: ghcr.io/percona/dbaas-catalog:latest
  grpcPodConfig:
    securityContextConfig: restricted
  updateStrategy:
    registryPoll:
      interval: 45m
EOF

echo
echo "########## install PSMDB"

cat <<EOF | kubectl apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: percona-server-mongodb-operator
  namespace: default
spec:
  channel: stable-v1
  installPlanApproval: Automatic
  name: percona-server-mongodb-operator
  source: dbaas-catalog
  sourceNamespace: olm
EOF

echo
echo "########## install PXC"

cat <<EOF | kubectl apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: percona-xtradb-cluster-operator
  namespace: default
spec:
  channel: stable-v1
  installPlanApproval: Automatic
  name: percona-xtradb-cluster-operator
  source: dbaas-catalog
  sourceNamespace: olm
EOF

echo
echo "########## install dbaas-operator"

cat <<EOF | kubectl apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: dbaas-operator
  namespace: default
spec:
  channel: stable-v0
  installPlanApproval: Automatic
  name: dbaas-operator
  source: dbaas-catalog
  sourceNamespace: olm
EOF

echo
echo "########## Done"
