#!/usr/bin/env bash
set -euo pipefail

ORG_NAME="acme"
ADMIN_USER="acme-admin"
ADMIN_PASS="AcmePass2026!"

echo "==> Resolving Gitea Route..."
GITEA_HOST=$(oc get route gitea -n git-server -o jsonpath='{.spec.host}')
BASE_URL="http://${ADMIN_USER}:${ADMIN_PASS}@${GITEA_HOST}/${ORG_NAME}"

echo "==> Seeding acme-control-plane repository..."
pushd seeds/acme-control-plane > /dev/null
rm -rf .git
git init -b main
git config user.name "ACME GitOps Bot"
git config user.email "bot@acme.corp"
git add .
git commit -m "feat: initial control-plane structure and application definitions"
git remote add origin "${BASE_URL}/acme-control-plane.git"
git push -u origin main --force
popd > /dev/null

echo "==> Seeding acme-workloads repository..."
pushd seeds/acme-workloads > /dev/null
rm -rf .git
git init -b main
git config user.name "ACME GitOps Bot"
git config user.email "bot@acme.corp"
git add .
git commit -m "feat: seed core workloads (order and inventory services)"
git remote add origin "${BASE_URL}/acme-workloads.git"
git push -u origin main --force
popd > /dev/null

echo "==> Repositories seeded successfully."