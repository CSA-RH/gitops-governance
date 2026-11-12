#!/usr/bin/env bash
set -euo pipefail

ORG_NAME="acme"
ADMIN_USER="acme-admin"
ADMIN_PASS="AcmePass2026!"
ADMIN_EMAIL="admin@acme.corp"

echo "==> Resolving Gitea Pod and Route..."
POD=$(oc get pod -n git-server -l app=gitea -o jsonpath='{.items[0].metadata.name}')
GITEA_HOST=$(oc get route gitea -n git-server -o jsonpath='{.spec.host}')

echo "==> Waiting for Gitea Route to respond with HTTP 200..."
until [ "$(curl -s -k -o /dev/null -w "%{http_code}" "http://${GITEA_HOST}/api/v1/version")" = "200" ]; do
  sleep 3
done

echo "==> Creating admin user '${ADMIN_USER}' via CLI..."
oc exec -n git-server "${POD}" -- \
  gitea --config /var/lib/gitea/app.ini --work-path /var/lib/gitea \
  admin user create --username "${ADMIN_USER}" --password "${ADMIN_PASS}" --email "${ADMIN_EMAIL}" --admin 2>/dev/null || true

echo "==> Creating organization '${ORG_NAME}' via REST API..."
STATUS_ORG=$(curl -s -k -o /dev/null -w "%{http_code}" -X POST "http://${GITEA_HOST}/api/v1/orgs" \
  -u "${ADMIN_USER}:${ADMIN_PASS}" \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"${ORG_NAME}\", \"full_name\": \"ACME Corporation\", \"visibility\": \"public\"}")
echo "    Organization '${ORG_NAME}': HTTP ${STATUS_ORG}"

echo "==> Creating repository 'acme-control-plane' in organization '${ORG_NAME}'..."
STATUS_CP=$(curl -s -k -o /dev/null -w "%{http_code}" -X POST "http://${GITEA_HOST}/api/v1/orgs/${ORG_NAME}/repos" \
  -u "${ADMIN_USER}:${ADMIN_PASS}" \
  -H "Content-Type: application/json" \
  -d '{"name": "acme-control-plane", "default_branch": "main", "private": false, "auto_init": false}')
echo "    Repository 'acme-control-plane': HTTP ${STATUS_CP}"

echo "==> Creating repository 'acme-workloads' in organization '${ORG_NAME}'..."
STATUS_WL=$(curl -s -k -o /dev/null -w "%{http_code}" -X POST "http://${GITEA_HOST}/api/v1/orgs/${ORG_NAME}/repos" \
  -u "${ADMIN_USER}:${ADMIN_PASS}" \
  -H "Content-Type: application/json" \
  -d '{"name": "acme-workloads", "default_branch": "main", "private": false, "auto_init": false}')
echo "    Repository 'acme-workloads': HTTP ${STATUS_WL}"

echo "==> Gitea initialization finished (201 = Created, 422 = Already exists)."