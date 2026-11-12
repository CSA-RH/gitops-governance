#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing Red Hat OpenShift GitOps Operator..."
oc apply -f platform/gitops-operator.yaml

echo "==> Waiting for ArgoCD CRDs to become available..."
until oc get crd argocds.argoproj.io >/dev/null 2>&1; do
  sleep 5
done

echo "==> Waiting for default ArgoCD instance in openshift-gitops..."
until oc get argocd openshift-gitops -n openshift-gitops >/dev/null 2>&1; do
  sleep 5
done

echo "==> Configuring Argo CD RBAC for CRC kubeadmin user..."
oc patch argocd openshift-gitops -n openshift-gitops --type merge -p '{
  "spec": {
    "rbac": {
      "scopes": "[groups, name, email]",
      "policy": "g, system:cluster-admins, role:admin\ng, cluster-admins, role:admin\ng, kube:admin, role:admin\ng, kubeadmin, role:admin\n"
    }
  }
}'

echo "==> Waiting for operator to spawn Argo CD Server and Controller resources..."
until oc get deployment openshift-gitops-server -n openshift-gitops >/dev/null 2>&1; do
  sleep 5
done
until oc get statefulset openshift-gitops-application-controller -n openshift-gitops >/dev/null 2>&1; do
  sleep 5
done

echo "==> Waiting for Argo CD Server and Application Controller rollouts..."
oc rollout status deployment/openshift-gitops-server -n openshift-gitops --timeout=300s
oc rollout status statefulset/openshift-gitops-application-controller -n openshift-gitops --timeout=300s

echo "==> OpenShift GitOps is ready."