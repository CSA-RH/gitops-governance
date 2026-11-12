.PHONY: help install-gitops deploy-gitea init-gitea seed bootstrap-argocd prepare-scenarios all clean-all

help:
	@echo "Available targets:"
	@echo "  make install-gitops    - Installs OpenShift GitOps Operator and configures kubeadmin RBAC"
	@echo "  make deploy-gitea      - Deploys Gitea on CRC and waits for readiness"
	@echo "  make init-gitea        - Creates admin user, 'acme' organization, and repositories"
	@echo "  make seed              - Pushes control-plane and workloads to Gitea"
	@echo "  make bootstrap-argocd  - Deploys Root Application into Argo CD"
	@echo "  make prepare-scenarios - Creates unmanaged live resources for adoption demos"
	@echo "  make all               - Executes full end-to-end bootstrap"
	@echo "  make clean-all         - Removes deployments, namespaces, and applications"

install-gitops:
	@chmod +x scripts/*.sh
	@./scripts/00-install-gitops.sh

deploy-gitea:
	@echo "==> Deploying Gitea..."
	oc apply -f platform/gitea.yaml
	@echo "==> Waiting for Gitea deployment rollout..."
	oc rollout status deployment/gitea -n git-server --timeout=180s

init-gitea:
	@chmod +x scripts/*.sh
	@./scripts/01-init-gitea.sh

seed:
	@chmod +x scripts/*.sh
	@./scripts/02-seed-repos.sh

bootstrap-argocd:
	@echo "==> Deploying Root Application..."
	oc apply -f seeds/acme-control-plane/bootstrap/root-application.yaml

prepare-scenarios:
	@echo "==> Deploying pre-existing unmanaged Application (legacy-billing)..."
	oc apply -f demo-scenarios/adoption/app-legacy-billing.yaml

all: install-gitops deploy-gitea init-gitea seed bootstrap-argocd prepare-scenarios
	@echo ""
	@echo "=============================================================="
	@echo " Bootstrap completed successfully."
	@echo " Argo CD Console (Log in via OpenShift with kubeadmin):"
	@echo " https://$$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')"
	@echo " Gitea Console:"
	@echo " http://$$(oc get route gitea -n git-server -o jsonpath='{.spec.host}') (acme-admin / AcmePass2026!)"
	@echo "=============================================================="

clean-all:
	oc delete application root-acme-apps legacy-billing -n openshift-gitops --ignore-not-found
	oc delete -f platform/gitea.yaml --ignore-not-found
	oc delete namespace acme-dev acme-test acme-prod acme-legacy --ignore-not-found