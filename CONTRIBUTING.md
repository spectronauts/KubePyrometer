# Contributing to KubePyrometer

Thanks for your interest in contributing! This document covers how to get started.

## Reporting issues

Open a [GitHub issue](https://github.com/spectronauts/KubePyrometer/issues/new) with:

- What you expected to happen
- What actually happened
- Steps to reproduce (cluster type, OS, config if possible)
- Relevant output (`summary.csv`, `failures.log`, phase logs)

For security vulnerabilities, see [SECURITY.md](SECURITY.md).

## Development setup

```bash
git clone https://github.com/spectronauts/KubePyrometer.git
cd KubePyrometer
```

Prerequisites: `bash` (4+), `kubectl`, `curl`. For local testing: `kind` and `docker`.

## Running the smoke test

The smoke test creates a Kind cluster, runs the harness with minimal parameters, and verifies all expected artifacts are produced:

```bash
bash lib/scripts/kind-smoke.sh
```

This is the same test that CI runs on every PR. Run it locally before submitting changes to make sure nothing is broken.

## Making changes

1. Fork the repo and create a branch from `main`
2. Make your changes
3. Run the smoke test locally: `bash lib/scripts/kind-smoke.sh`
4. Open a pull request against `main`

### What lives where

| Path | Purpose |
|------|---------|
| `kubepyrometer` | CLI entry point (subcommand dispatch) |
| `lib/run.sh` | Core harness engine |
| `lib/scripts/` | Helper scripts (install, load images, summarize, etc.) |
| `lib/templates/` | Kubernetes object templates (Go-templated YAML) |
| `lib/workloads/` | kube-burner job definitions |
| `lib/manifests/` | Static Kubernetes manifests (RBAC) |
| `lib/configs/` | Config profiles |
| `Makefile` | Install / uninstall / dist targets |
| `.github/workflows/` | CI and release automation |

### Code style

- Shell scripts use `bash` with `set -euo pipefail`
- Indent with 2 spaces
- Quote all variable expansions
- No unnecessary comments -- code should be self-explanatory

## Releases

Releases are automated via GitHub Actions. When a tag matching `v*` is pushed, the workflow builds a tarball and creates a GitHub Release. The Homebrew formula lives in [spectronauts/homebrew-kubepyrometer](https://github.com/spectronauts/homebrew-kubepyrometer) and is updated separately.

## License

By contributing, you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE).
