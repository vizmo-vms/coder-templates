---
display_name: Hetzner Cloud VM (Linux)
description: Provision Hetzner Cloud Linux VMs as Coder workspaces
icon: /emojis/2601-fe0f.png
maintainer_github: coder
verified: true
tags: [vm, linux, hetzner, hcloud]
---

# Remote Development on Hetzner Cloud VMs (Linux)

Provision Hetzner Cloud Linux VMs as [Coder workspaces](https://coder.com/docs/v2/latest/workspaces) with this example template.

## What this template gives you

- Hetzner Cloud workspace VMs in Falkenstein (`fsn1`)
- Fixed server choices: `cx43` or `cx53`
- Public IPv4 and IPv6 on each workspace server
- Persistent `100 GiB` volume mounted at `/home/<username>`
- No SSH access and no root-password email, when created with a pre-existing Hetzner SSH key name
- Shared firewall support through the `coder_workspace=true` label

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

The key is used only at server creation time so Hetzner does not send the root password by email. SSH is still disabled by this template in two places:

- no inbound SSH rule exists in the shared firewall
- cloud-init disables and masks the SSH service inside the VM

### IPv6 reachability

## Architecture

This template provisions the following resources per workspace:

- Hetzner Cloud server (ephemeral, deleted on workspace stop)
- Hetzner Cloud volume (persistent, reattached and mounted at `/home/<username>`)

When a workspace stops, the VM is deleted. On the next start, a new VM is created and the existing home volume is reattached, preserving user files in `/home/<username>`.

Network and firewall resources are shared and are not created by this template.

## Networking Notes

### Why is there no IPv4?

This template creates both a public IPv4 and IPv6 address:

- `ipv4_enabled = true`
- `ipv6_enabled = true`

This ensures the Coder agent inside the workspace can reliably reach your `coderd` URL regardless of IPv6 availability.

### Can I use SSH anyway?

Not with this template as written. It is intentionally built for Coder-managed access only.

If you later want SSH, you would need to change both the shared firewall and the cloud-init hardening in this template.

> **Note**
> This template is designed to be a starting point. Edit the Terraform to fit your image, tooling, and security requirements.
