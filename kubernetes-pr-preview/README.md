---
display_name: Kubernetes Preview Pod
description: Provision Kubernetes-backed Coder workspaces for PR preview environments
icon: /icon/k8s.png
maintainer_github: vizmo-vms
verified: false
tags: [container, kubernetes, preview, sysbox, docker]
---

# Remote Development on Kubernetes Preview Pods

Provision Kubernetes pods as [Coder workspaces](https://coder.com/docs/v2/latest/workspaces) for PR preview environments.

This template is based on Coder's Kubernetes example and mirrors the preview app surface from the Hetzner preview template.

## What this template gives you

- One Kubernetes Deployment per running workspace
- One persistent home PVC mounted at `/home/<workspace owner>`
- Configurable CPU, memory, and home disk size
- Ubuntu package bootstrap for Git, curl, jq, GitHub CLI, Vault CLI, Node.js 22,
  pnpm, Docker, Docker Compose, Temporal CLI, Starship, and canvas/build dependencies
- code-server installed by the workspace agent startup script
- Sysbox RuntimeClass support for Docker-in-workspace
- Workspace agent, code-server, and preview bootstrap run as the actual Coder
  workspace owner, not as a hardcoded `coder` user
- Boot-time preview bootstrap that runs `~/.preview/start.sh` when present
- Coder apps for Portal, Touchless, Server, LiveQuery, Temporal UI, Sendria,
  Parse Dashboard, and Shlink
- Preview apps shared with authenticated Coder users through subdomain routing
- Intended Coder default autostop/sleep time of 30 minutes

## Prerequisites

### Kubernetes access

The Kubernetes provider defaults to an explicit kubeconfig path:

```hcl
kubeconfig_path = "/home/coder/.kube/config"
```

That file must exist inside the Coder provisioner container or pod, which is the
process that runs Terraform. If your kubeconfig is mounted somewhere else, set
`kubeconfig_path` to that path. To use in-cluster Kubernetes credentials instead,
set `kubeconfig_path = ""` and make sure the provisioner pod has suitable RBAC.

The target namespace must already exist. The template defaults to `preview`.

### Persistent storage

The template defaults workspace home PVCs to the `ssd-large` StorageClass. Override `storage_class_name` if your cluster uses a different StorageClass.

### Sysbox

This template expects Sysbox to be installed on the Kubernetes nodes and a
RuntimeClass named `sysbox-runc` to exist. If your RuntimeClass has another name,
set:

```hcl
runtime_class_name = "your-sysbox-runtime-class"
```

The Deployment sets `hostUsers: false` because Kubernetes 1.33 with Sysbox can
otherwise fail container creation while mounting `sysfs`.

### Workspace image

The default image pins Coder's Ubuntu base image to Ubuntu 24.04 Noble:

```hcl
workspace_image = "codercom/enterprise-base:ubuntu-noble"
```

Coder's current image repository documents `codercom/example-base:ubuntu-noble`
as the recommended new name and keeps `codercom/enterprise-base:*` as a
backward-compatible alias. This template uses the enterprise alias to stay close
to Coder's Kubernetes and Sysbox examples.

The startup script assumes an Ubuntu/Debian-style image with `apt-get` and
passwordless `sudo`, which the Coder Ubuntu base image provides. For faster and
more reliable preview startup, bake these packages into a custom image and set
`workspace_image` to that image.

### Automatic sleep

Coder stores the default autostop duration as template metadata, not in this workspace `main.tf`. Set it to 30 minutes when creating or editing this template:

```bash
coder templates create kubernetes-pr-preview --default-ttl 30m
coder templates edit kubernetes-pr-preview --default-ttl 30m --activity-bump 30m
```

If the Coder deployment does not allow a 30-minute default TTL, use `1h` with the same flag.

## Architecture

This template provisions the following resources per workspace:

- Kubernetes PersistentVolumeClaim for `/home/<workspace owner>`
- Kubernetes Deployment with one Sysbox-backed workspace pod while the workspace is running
  using a readable `coder-<workspace name>-<short id>` name
- Coder apps for Portal, Touchless, Server, LiveQuery, Temporal UI, Sendria,
  Parse Dashboard, and Shlink

When a workspace stops, the Deployment is deleted. On the next start, a new pod is created and the existing home PVC is reattached, preserving user files under `/home/<workspace owner>`.

The preview apps do not require Kubernetes Services or Ingresses. Coder proxies the local ports through the workspace agent and publishes them as authenticated Coder apps.

## Preview bootstrap

If `/home/<workspace owner>/.preview/start.sh` exists and is executable, the agent startup script launches it in the background and writes logs to `/home/<workspace owner>/.preview/start.log`.

The pod starts as root only long enough to create or rename the Linux user to the
Coder workspace owner, grant passwordless sudo, and then exec the Coder agent as
that user. The agent startup script installs Docker and starts `dockerd` with
Docker data under the user's home directory.

> **Note**
> This template is designed to be a starting point. Edit the namespace, image, resources, storage class, and bootstrap behavior to fit your cluster and preview workload.
