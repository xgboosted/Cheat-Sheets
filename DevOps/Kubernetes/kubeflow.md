# Kubeflow 1.9 — Single-command installer (Minikube)

Minimal steps to run the single-command installer from the `kubeflow/manifests` repo (release-1.9). Run these on the machine where `kubectl` points to your Minikube cluster.

Prerequisites
- kubectl configured and pointing to the Minikube cluster
- kustomize v5.4.3+ installed
- git installed
- Enough cluster resources (recommend 8+ CPUs, 16+ GB RAM, 50+ GB disk)

Commands

1. Clone and checkout release-1.9 (fallback to master if branch missing)
```bash
git clone https://github.com/kubeflow/manifests.git
cd manifests
git fetch --all --tags
if git rev-parse --verify --quiet origin/release-1.9 >/dev/null; then
  git checkout origin/release-1.9 -b release-1.9
elif git rev-parse --verify --quiet release-1.9 >/dev/null; then
  git checkout release-1.9
else
  git checkout master
fi
```

2. Ensure kubectl context is `minikube`
```bash
kubectl config use-context minikube
```

3. Run the single-command installer (retries until resources accept)
```bash
while ! kustomize build example | kubectl apply --server-side --force-conflicts -f -; do
  echo "Retrying to apply resources"
  sleep 20
done
```

Access the Central Dashboard (after pods are ready)
```bash
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80
# then open http://localhost:8080
```

Notes
- The retry loop is required because some CRs may be applied before their CRDs become established; re-running allows the apply to succeed once CRDs are ready.
- For resource or image-pull issues, increase Minikube resources or provide image registry credentials.
- Use `kubectl get pods -A` to monitor progress; full deployment can take 10–30+ minutes depending on resources and network.

---

# How to log in to the Kubeflow Central Dashboard

Follow these concise steps to reach the dashboard and sign in.

## 1 — Expose the ingress (port-forward)
Run this locally where your kubectl points to the Minikube cluster:

```bash
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80
# open http://localhost:8080 in your browser
```

(Alternatively use `minikube tunnel` if your overlay expects LoadBalancer services and you have configured ingress hostnames.)

## 2 — Default credentials (if manifests used the default Dex static user)
- Email: `user@example.com`  
- Password: `12341234`

Use these on the Dex login screen presented by the Central Dashboard.

## 3 — Change the Dex password (optional, recommended)
Generate a bcrypt hash locally and replace the cluster secret:

```bash
# generate bcrypt hash (install passlib if needed)
python3 -c 'from passlib.hash import bcrypt; import getpass; print(bcrypt.using(rounds=12, ident="2y").hash(getpass.getpass()))'
# copy the output hash
```

Replace the secret and restart Dex:

```bash
kubectl -n auth delete secret dex-passwords || true
kubectl -n auth create secret generic dex-passwords --from-literal=DEX_USER_PASSWORD='<PASTE_HASH>'
kubectl -n auth delete pods -l app.kubernetes.io/name=dex
# wait for dex pod to restart, then log in with the new password
```

## 4 — Troubleshooting
- Ensure required pods are Running:
```bash
kubectl -n istio-system get pods
kubectl -n auth get pods
kubectl -n kubeflow get pods
```
- If login page doesn't load, check Dex logs:
```bash
kubectl -n auth logs -l app.kubernetes.io/name=dex --tail=200
```
- If services are not reachable, use `kubectl get svc -n istio-system` to inspect the ingress and ensure port-forward or tunnel is active.

## Notes
- Some deployments use oauth2-proxy/Dex with different default accounts—consult your manifests overlays if the defaults were changed.
- For production, configure an external OIDC/IDP instead of static Dex passwords.

---

# Multi-user guidance for Kubeflow on Minikube

Short answer
- Yes, multiple people can log in concurrently using the same account, but this is discouraged. Use individual accounts for each user for security, auditability, and namespace isolation.

Why individual accounts are recommended
- Isolation: Kubeflow uses Profiles to create per-user namespaces and apply resource isolation/quotas.
- Auditing / accountability: Distinct users allow tracking who performed actions.
- Access control: Per-user RBAC is possible with Profiles + KFAM.
- Quotas & isolation: Easier to allocate resources and enforce policies per user.

Recommended approaches
1. Use an external OIDC/IDP with Dex (recommended for multiple users)
   - Configure Dex to talk to your identity provider (Google, GitHub, Azure AD, Keycloak, etc.)
   - Advantages: centralized user management, MFA, RBAC, no static passwords to maintain.

2. Use Kubeflow Profiles (create a Profile per user)
   - Example Profile resource (replace email/name):
```yaml
apiVersion: kubeflow.org/v1
kind: Profile
metadata:
  name: user-example-com
spec:
  owner:
    kind: User
    name: user@example.com
```
Apply:
```bash
kubectl apply -f profile-user-example-com.yaml
```
This creates a namespace and wiring for that user; use one Profile per user.

3. Static Dex users (only for local/dev, not production)
   - You can add multiple `staticPasswords` in Dex config (common/dex/base or overlay) or patch the Dex ConfigMap using a kustomize overlay.
   - Not recommended: static creds lack lifecycle controls and auditing.

4. Create service accounts for automation
   - For CI or automated agents, create Kubernetes ServiceAccount and bind RBAC roles as needed.
   - Use oauth2-proxy/token-based approaches if you need web UI access for services.

Practical commands (quick)
- Port-forward UI and log in as distinct users via your IDP or Dex:
```bash
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80
# open http://localhost:8080
```
- Create a Profile for a user (inline):
```bash
cat <<EOF | kubectl apply -f -
apiVersion: kubeflow.org/v1
kind: Profile
metadata:
  name: alice-example-com
spec:
  owner:
    kind: User
    name: alice@example.com
EOF
```

Notes
- After adding users, ensure appropriate quotas/limits are configured for their namespaces.
- For production-like multi-user setups, integrate an IDP (OIDC) with Dex or use oauth2-proxy configuration described in the manifests.
