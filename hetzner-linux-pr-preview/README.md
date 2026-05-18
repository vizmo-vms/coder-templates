---
display_name: Hetzner Preview VM (Linux)
description: Provision Hetzner Cloud Linux VMs as Coder workspaces for PR preview environments
icon: /emojis/2601-fe0f.png
maintainer_github: vizmo-vms
verified: false
tags: [vm, linux, hetzner, hcloud, preview]
---

# Remote Development on Hetzner Cloud VMs (Linux)

Provision Hetzner Cloud Linux VMs as [Coder workspaces](https://coder.com/docs/v2/latest/workspaces) with this example template.

This template variant is intended for PR preview environments.

## What this template gives you

- Hetzner Cloud workspace VMs in a selectable location: Falkenstein (`fsn1`), Nuremberg (`nbg1`), or Helsinki (`hel1`)
- Fixed server choices: `cpx32`, `cpx42`, or `cpx52`
- Built-in validation that blocks server types unavailable in the selected location
- Public IPv4 on each workspace server
- Persistent `30 GiB` volume mounted at `/home/<username>`
- Node.js LTS 22 with `pnpm` installed for the workspace user
- No SSH access and no root-password email, when created with a pre-existing Hetzner SSH key name
- Shared firewall support through the `coder_workspace=true` label
- Boot-time preview bootstrap service that runs `~/.preview/start.sh` when present
- Intended Coder default autostop/sleep time of 30 minutes

## Prerequisites

### Authentication

This template expects the Hetzner Cloud provider token to be available to `coderd` as `HCLOUD_TOKEN`.

For example, if `coderd` runs as a system service, set the environment variable for that service user and restart `coderd`.

Terraform provider docs:
- https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs

### Create the shared firewall first

Apply the shared firewall config in [`../hetzner-shared-firewall`](../hetzner-shared-firewall) once per Hetzner project before users create workspaces from this template.

That firewall attaches automatically to servers labeled `coder_workspace=true`, which this template applies to every workspace VM and home volume.

### Create a Hetzner SSH key

Create one SSH key in the Hetzner project named `hetzner` in coder server home folder.

The key is used only at server creation time so Hetzner does not send the root password by email. SSH is still blocked by the shared firewall:

- no inbound SSH rule exists in the shared firewall

### IPv6 reachability

### Automatic sleep

Coder stores the default autostop duration as template metadata, not in this workspace `main.tf`. Set it to 30 minutes when creating or editing this template:

```bash
coder templates create hetzner-linux-pr-preview --default-ttl 30m
coder templates edit hetzner-linux-pr-preview --default-ttl 30m --activity-bump 30m
```

If the Coder deployment does not allow a 30-minute default TTL, use `1h` with the same flag.

## Architecture

This template provisions the following resources per workspace:

- Hetzner Cloud server (ephemeral, deleted on workspace stop)
- Hetzner Cloud volume (persistent, reattached and mounted at `/home/<username>`)

When a workspace stops, the VM is deleted. On the next start, a new VM is created and the existing home volume is reattached, preserving user files in `/home/<username>`.

Network and firewall resources are shared and are not created by this template.

## Networking Notes

### Why is IPv4 enabled?

This template creates a public IPv4 address and does not create a public IPv6 address:

- `ipv4_enabled = true`
- `ipv6_enabled = false`

This ensures the Coder agent inside the workspace can reliably reach your `coderd` URL.

### Can I use SSH anyway?

Not with this template as written. It is intentionally built for Coder-managed access only.

If you later want SSH, you would need to change both the shared firewall and the server setup in this template.

> **Note**
> This template is designed to be a starting point. Edit the Terraform to fit your image, tooling, and security requirements.
