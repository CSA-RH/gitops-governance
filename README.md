# Enterprise GitOps Governance on OpenShift (App of Apps & ApplicationSets)

A self-contained, reproducible demonstration environment built for **Red Hat OpenShift Local (CRC)**. It showcases how to manage Argo CD `Application` and `ApplicationSet` resources declaratively from Git—eliminating manual `oc apply` operations, enforcing RBAC governance, and enabling zero-downtime adoption of existing cluster workloads.

---

## Architecture Overview

This repository (`gitops-governance`) acts strictly as the **bootstrap and orchestration kit**. It is not watched by Argo CD. Instead, it provisions a self-hosted **Gitea** instance inside CRC and seeds two internal repositories under the `acme` organization to mirror an enterprise GitOps topology:

```text
[GitHub: gitops-governance] (Bootstrapper / Orchestrator)
       │
       │  make all
       ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Red Hat OpenShift Local (CRC Cluster)                                │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │ Namespace: git-server (Internal Git Provider - Gitea)          │  │
│  │  ├── acme/acme-control-plane  ──► Argo CD Apps & AppSets       │  │
│  │  └── acme/acme-workloads      ──► Kubernetes / Kustomize YAML  │  │
│  └────────────────────────────────────────────────────────────────┘  │
│               ▲                                   ▲                  │
│               │ (1) Root App watches              │ (2) AppSet       │
│               │     /domains                      │     generates    │
│  ┌────────────┴───────────────────────────────────┴───────────────┐  │
│  │ Namespace: openshift-gitops (Red Hat OpenShift GitOps)         │  │
│  │  ├── Application: root-acme-apps (App of Apps / AppSets)       │  │
│  │  ├── ApplicationSet: appset-core-services (Matrix Generator)   │  │
│  │  ├── Child Apps: order-{dev,test,prod}, inventory-{dev,test,prod} │
│  │  └── Unmanaged App (Pre-existing): legacy-billing              │  │
│  └────────────────────────────────────────────────────────────────┘  │
│               │                                   │                  │
│               ▼                                   ▼                  │
│  ┌─────────────────────────────────┐  ┌───────────────────────────┐  │
│  │ Managed Fleet Namespaces        │  │ Brownfield Namespace      │  │
│  │  ├── acme-dev  (order, inv.)    │  │  └── acme-legacy          │  │
│  │  ├── acme-test (order, inv.)    │  │       └── legacy-billing  │  │
│  │  └── acme-prod (order, inv.)    │  │                           │  │
│  └─────────────────────────────────┘  └───────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

### Key Technical Highlights
* **Rootless OpenShift Security:** Gitea runs under OpenShift's default `restricted-v2` SCC without requiring `anyuid`, dynamically binding `RUN_USER` to the namespace's assigned runtime UID.
* **Automated Namespace Governance:** Uses `managedNamespaceMetadata` to inject `argocd.argoproj.io/managed-by: openshift-gitops` upon namespace creation, automatically granting the Argo CD controller namespace-scoped RBAC permissions.
* **SSO RBAC Configured Out-of-the-Box:** Patches the `ArgoCD` CR so `kubeadmin` (`kube:admin`) inherits `role:admin` when logging in via OpenShift OAuth.

---

## Repository Structure

```text
gitops-governance/
├── Makefile                                  # End-to-end automation targets
├── demo-scenarios/
│   └── adoption/
│       └── app-legacy-billing.yaml           # Imperative app simulating an unmanaged legacy workload
├── platform/
│   ├── gitops-operator.yaml                  # OpenShift GitOps Operator Subscription
│   └── gitea.yaml                            # Gitea Deployment, PVC, Service, Route & probes
├── scripts/
│   ├── 00-install-gitops.sh                  # Installs operator, waits for CRDs, configures kubeadmin RBAC
│   ├── 01-init-gitea.sh                      # Creates admin user, 'acme' org, and repos via Gitea API
│   └── 02-seed-repos.sh                      # Pushes initial seeds to internal Gitea repositories
└── seeds/
    ├── acme-control-plane/                   # Seeded into http://.../acme/acme-control-plane.git
    │   ├── bootstrap/
    │   │   └── root-application.yaml         # Single bootstrap entry point watching /domains
    │   └── domains/
    │       └── core-services/
    │           └── appset-core-services.yaml # Matrix ApplicationSet (workloads/* x {dev,test,prod})
    └── acme-workloads/                       # Seeded into http://.../acme/acme-workloads.git
        ├── standalone/
        │   └── legacy-billing/               # Workload manifests for the brownfield adoption demo
        └── workloads/
            ├── inventory/                    # Kustomize base + dev/test/prod overlays
            └── order/                        # Kustomize base + dev/test/prod overlays
```

---

## Prerequisites

* **Red Hat OpenShift Local (CRC)** installed on your workstation.
* CLI tools: `oc`, `git`, `curl`, and `python3`.
* **Cluster Sizing:** Allocate at least **14 GB RAM** and **6 vCPUs** to CRC to run OpenShift GitOps, Gitea, and all demo workloads simultaneously:

```bash
crc config set memory 14336
crc config set cpus 6
crc setup
crc start
```

---

## Quick Start (Bootstrap)

1. Log in to your CRC cluster as `kubeadmin`:
   ```bash
   eval $(crc oc-env)
   oc login -u kubeadmin [https://api.crc.testing:6443](https://api.crc.testing:6443)
   ```

2. Run the full automated bootstrap:
   ```bash
   make all
   ```
   This single target executes:
   * `install-gitops`: Installs the Red Hat OpenShift GitOps Operator and applies the `kubeadmin` RBAC policy.
   * `deploy-gitea`: Deploys Gitea in `git-server` and waits for its readiness probe.
   * `init-gitea`: Creates `acme-admin`, the `acme` organization, and the two Git repositories.
   * `seed`: Pushes `acme-control-plane` and `acme-workloads` into Gitea.
   * `bootstrap-argocd`: Applies `root-application.yaml` into `openshift-gitops`.
   * `prepare-scenarios`: Imperatively creates `legacy-billing` outside of `root-acme-apps` to stage the adoption scenario.

### Access & Credentials

| Component | URL Discovery Command | Credentials |
| :--- | :--- | :--- |
| **Argo CD UI** | `echo "https://$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')"` | Click **Log in via OpenShift** (`kubeadmin`) |
| **Gitea UI** | `echo "http://$(oc get route gitea -n git-server -o jsonpath='{.spec.host}')"` | User: `acme-admin` / Pass: `AcmePass2026!` |

---

## Demo Walkthroughs

Once `make all` finishes, open the Argo CD UI. You will observe `root-acme-apps` managing `appset-core-services` (which spawns 6 child applications across `acme-dev`, `acme-test`, and `acme-prod`), alongside `legacy-billing` sitting independently as an unmanaged top-level application.

### Scenario 1: Scaling Workloads Across Environments with `ApplicationSets`

**Objective:** Show how a single `ApplicationSet` using a **Matrix Generator** eliminates manual `Application` definitions when rolling out standardized services across multiple environments (`dev`, `test`, `prod`).

1. Inspect `appset-core-services` in Argo CD. It pairs every folder matching `workloads/*` in `acme-workloads` with the environment list `[dev, test, prod]`.
2. Verify environment-specific configuration via Kustomize overlays by querying the deployed routes:
   ```bash
   curl -s "http://$(oc get route order-service -n acme-dev -o jsonpath='{.spec.host}')"
   curl -s "http://$(oc get route order-service -n acme-prod -o jsonpath='{.spec.host}')"
   ```
3. **Live Scale-Out:** Clone `acme-workloads`, duplicate `workloads/order` into `workloads/analytics` (updating names and `RESPONSE` strings), and push to `main`:
   ```bash
   GITEA_HOST=$(oc get route gitea -n git-server -o jsonpath='{.spec.host}')
   git clone "http://acme-admin:AcmePass2026!@${GITEA_HOST}/acme/acme-workloads.git" /tmp/acme-workloads

   cp -r /tmp/acme-workloads/workloads/order /tmp/acme-workloads/workloads/analytics
   find /tmp/acme-workloads/workloads/analytics -type f -exec sed -i.bak 's/order-service/analytics-service/g; s/Order Service/Analytics Service/g' {} +
   find /tmp/acme-workloads/workloads/analytics -name "*.bak" -delete

   cd /tmp/acme-workloads
   git add . && git commit -m "feat: add analytics workload across all environments" && git push
   ```
4. Refresh `appset-core-services` in Argo CD: **3 new applications** (`analytics-dev`, `analytics-test`, `analytics-prod`) are automatically generated and synced with zero changes to `acme-control-plane`.

---

### Scenario 2: Onboarding a New Standalone `Application`

**Objective:** Show how bespoke applications are onboarded strictly via Git commits in the control-plane repository, without granting developers `oc apply` permissions on `openshift-gitops`.

1. Clone `acme-control-plane` and add a new domain folder containing a standalone `Application` manifest:
   ```bash
   GITEA_HOST=$(oc get route gitea -n git-server -o jsonpath='{.spec.host}')
   git clone "http://acme-admin:AcmePass2026!@${GITEA_HOST}/acme/acme-control-plane.git" /tmp/acme-control-plane

   mkdir -p /tmp/acme-control-plane/domains/observability
   cat << 'EOF' > /tmp/acme-control-plane/domains/observability/app-status-page.yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: status-page
     namespace: openshift-gitops
     finalizers:
       - resources-finalizer.argocd.argoproj.io
   spec:
     project: default
     source:
       repoURL: '[http://gitea.git-server.svc.cluster.local:3000/acme/acme-workloads.git](http://gitea.git-server.svc.cluster.local:3000/acme/acme-workloads.git)'
       targetRevision: main
       path: workloads/inventory/overlays/prod
     destination:
       server: '[https://kubernetes.default.svc](https://kubernetes.default.svc)'
       namespace: acme-observability
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
       syncOptions:
         - CreateNamespace=true
       managedNamespaceMetadata:
         labels:
           argocd.argoproj.io/managed-by: openshift-gitops
   EOF

   cd /tmp/acme-control-plane
   git add . && git commit -m "feat(observability): onboard status-page application" && git push
   ```
2. Refresh `root-acme-apps` in Argo CD: `status-page` appears in the application tree, creates `acme-observability`, and deploys its pods automatically.

---

### Scenario 3: Zero-Downtime Adoption of Pre-Existing `Applications`

**Objective:** Demonstrate how organizations with hundreds of existing, manually applied Argo CD `Applications` can bring them under central GitOps governance **without deleting or restarting running workloads**.

1. **Check Pre-Existing Pod Uptime:** Note the pod name and `AGE` of `legacy-billing` running in `acme-legacy`:
   ```bash
   oc get pods -n acme-legacy
   ```
   In the Argo CD UI, notice that `legacy-billing` is currently detached from `root-acme-apps`.

2. **Export & Sanitize Live Manifest:** Export the live `Application` resource from the cluster, stripping Kubernetes runtime fields (`uid`, `resourceVersion`, `status`, `managedFields`, etc.), and commit it to `acme-control-plane`:
   ```bash
   GITEA_HOST=$(oc get route gitea -n git-server -o jsonpath='{.spec.host}')
   git clone "http://acme-admin:AcmePass2026!@${GITEA_HOST}/acme/acme-control-plane.git" /tmp/acme-control-plane-adopt
   mkdir -p /tmp/acme-control-plane-adopt/domains/billing

   oc get application legacy-billing -n openshift-gitops -o json | python3 -c '
   import sys, json
   app = json.load(sys.stdin)
   for k in ["uid", "resourceVersion", "generation", "creationTimestamp", "managedFields", "annotations", "labels"]:
       app["metadata"].pop(k, None)
   app.pop("status", None)
   app.pop("operation", None)
   print(json.dumps(app, indent=2))
   ' > /tmp/acme-control-plane-adopt/domains/billing/app-legacy-billing.json

   cd /tmp/acme-control-plane-adopt
   git add . && git commit -m "chore(adoption): bring legacy-billing under control-plane governance" && git push
   ```

3. **Verify Non-Disruptive Adoption:**
   * In Argo CD, `root-acme-apps` detects `Application/legacy-billing`, applies tracking metadata (`argocd.argoproj.io/tracking-id`), and nests it cleanly under the root hierarchy.
   * Re-check the running workload pod:
     ```bash
     oc get pods -n acme-legacy
     ```
     The pod name and `AGE` remain unchanged—proving zero downtime during governance migration.

---

## Scaling Governance to 600+ Applications

When scaling this pattern across enterprise clusters with hundreds of applications, apply the following architectural practices:

* **The 90/10 Rule (Fleet AppSets vs. Bespoke Apps):** Avoid creating 600 static `Application` YAMLs. Group 90% of standardized microservices into 10–20 domain-level `ApplicationSets` using Matrix or Git generators, reserving individual `Application` files only for bespoke legacy workloads.
* **Domain Partitioning & `CODEOWNERS`:** Organize `acme-control-plane/domains/` by business unit (`payments/`, `channels/`, `core-banking/`) and pair directories with Git `CODEOWNERS` and dedicated Argo CD `AppProjects` to delegate self-service approvals safely.
* **Safe Migration Safeguard:** Omit `resources-finalizer.argocd.argoproj.io` from `Application` manifests during initial brownfield adoption. If an imported `Application` file is accidentally deleted from the control-plane repository, Argo CD will remove only the `Application` metadata object while leaving live production pods untouched.
* **Controller Sharding & Reconciliation Tuning:** Beyond 500 applications per cluster, scale `ARGOCD_CONTROLLER_REPLICAS` to `3` in the `ArgoCD` CR to shard reconciliation loops, increase `timeout.reconciliation` to `600s`, and configure Git webhooks for event-driven syncs.

### Avoiding the Monorepo Bottleneck (`manifest-generate-paths`)

While this demo uses a single `acme-workloads` repository for simplicity, pointing **600+ Applications** to a single monolithic repository without path filtering creates a severe performance bottleneck:

1. **Webhook & Cache Invalidation Storms:** By default, any commit to `main` invalidates the manifest cache for every `Application` tracking that repository. A one-line change in a single service forces `argocd-repo-server` to re-render all 600+ manifests simultaneously.
2. **PR Queue Contention & Blast Radius:** Hundreds of developers merging into a single repository causes constant Git contention and widens the impact of misconfigured shared bases.

**Mitigation Strategy:**
* **Partition by Domain:** Split workload repositories by business unit or domain (e.g., `payments-workloads`, `core-workloads`) rather than maintaining a single global monorepo.
* **Enforce `manifest-generate-paths`:** Annotate generated `Applications` so Argo CD only triggers manifest rendering when files inside that specific application's directory—or its shared Kustomize `base`—are modified:

```yaml
# Inside ApplicationSet template.metadata.annotations:
metadata:
  name: '{{path.basename}}-{{env}}'
  annotations:
    # Re-render only if changes occur in the overlay (.) or its shared base (../../base)
    argocd.argoproj.io/manifest-generate-paths: '.;../../base'
```

---

## Cleanup

To remove all demo applications, target namespaces, and Gitea while preserving the OpenShift GitOps Operator:

```bash
make clean-all
rm -rf /tmp/acme-workloads /tmp/acme-control-plane /tmp/acme-control-plane-adopt
```