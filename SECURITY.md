# Security Policy

## Supported Versions

| Version              | Supported          |
|----------------------|--------------------|
| v0.3.x (preview)     | Yes (pre-release)  |
| v0.2.x               | Yes                |
| v0.1.x               | Yes                |

## Reporting a Vulnerability

If you discover a security issue in KubePyrometer, please report it privately by emailing **carlosatspectro@users.noreply.github.com** or by opening a [GitHub Security Advisory](https://github.com/spectronauts/KubePyrometer/security/advisories/new).

Do not open a public issue for security vulnerabilities. You should receive an acknowledgment within 72 hours.

## Security Model

KubePyrometer is a load-testing tool that intentionally creates resource pressure on Kubernetes clusters. Its security posture is designed around least privilege and isolation.

### RBAC (Least Privilege)

The harness creates a dedicated `probe-sa` ServiceAccount in the `kb-probe` namespace with the minimum permissions needed:

- **ClusterRole** -- Read-only access to `/readyz`, `/healthz`, `/livez` (nonResourceURLs) and `get`/`list` on `nodes`
- **Role (kube-system only)** -- `get`/`list` on `configmaps`, scoped to `kube-system`
- **No write access** -- The probe SA cannot create, update, or delete any resources
- **No secrets access** -- The probe SA has no access to Secrets in any namespace

Review the full RBAC manifest before applying: `lib/manifests/probe-rbac.yaml`

### Pod Security

All pods created by the harness (stress and probe) run as unprivileged containers:

- No `privileged: true`
- No `NET_ADMIN` or other elevated capabilities
- No host networking, host PID, or host IPC
- No PersistentVolumeClaims (disk stress uses `emptyDir`)
- All images set `imagePullPolicy: IfNotPresent`

### Supply Chain

**kube-burner binary.** The harness downloads kube-burner from [GitHub Releases](https://github.com/kube-burner/kube-burner/releases) over HTTPS. The download is pinned to a specific version (v2.4.0) and the installed binary is version-checked before use. To eliminate the download entirely, pre-install the binary and point to it with `KB_BIN=/path/to/kube-burner`.

**Container images.** The harness bundles `busybox:1.36.1` and `bitnami/kubectl:1.35.2` as `lib/images/harness-images.tar`. These are unmodified upstream images. To verify integrity, rebuild the tar from upstream sources:

```bash
bash lib/scripts/save-images.sh
```

For air-gapped or hardened environments, use the registry redirect feature (`-r` / `IMAGE_MAP_FILE`) to pull images from a trusted internal registry instead.

## Best Practices

### Before Running

1. **Never run against production without testing first.** Use a Kind cluster (`lib/scripts/kind-smoke.sh`) or a dedicated test cluster to validate behavior before targeting shared or production infrastructure.

2. **Audit the RBAC manifest.** Review `lib/manifests/probe-rbac.yaml` to confirm the permissions are acceptable for your cluster's security policy. The harness applies this manifest automatically on every run.

3. **Verify your kubectl context.** The harness operates on whatever cluster `kubectl` is pointing at. Confirm with `kubectl config current-context` and `kubectl get nodes` before starting.

4. **Use a dedicated kubeconfig identity.** If possible, use a service account or role-bound identity with only the permissions needed (create namespaces, deployments, jobs, RBAC resources in the `kb-probe` and `kb-stress-*` namespaces).

### During Runs

5. **Start with conservative defaults.** The default settings (1 replica, 50m CPU, 32 Mi memory, 2 ramp steps) are intentionally small. Increase gradually.

6. **Monitor the cluster externally.** Watch node conditions (`kubectl top nodes`) and API server metrics from outside the harness during runs to catch unexpected pressure.

7. **Know how to clean up manually.** If the harness is interrupted (e.g., Ctrl-C), stress pods may remain. Delete them with:

```bash
kubectl delete ns -l app=kb-stress
kubectl delete ns kb-probe
```

### Network and Registry

8. **Air-gapped clusters.** Use registry redirect (`-r` or `IMAGE_MAP_FILE`) to rewrite image references to an internal mirror. Supply a pre-created `imagePullSecrets` Secret name via `IMAGE_PULL_SECRET`.

9. **Restrict egress if needed.** The only external network access the harness requires is the initial kube-burner download from `github.com` (skipped if the binary is already present). All in-cluster traffic stays within the cluster. Network stress targets the harness's own `net-echo` echo server (`net-echo:8080`), not any external endpoint.

### After Runs

10. **Review RBAC cleanup.** The harness does not delete the `kb-probe` namespace or its RBAC resources after a run. Remove them when testing is complete:

```bash
kubectl delete -f lib/manifests/probe-rbac.yaml
```
