---
display_name: Oracle Cloud VM (Linux, Preemptible)
description: Provision Oracle Cloud preemptible VMs as Coder workspaces
icon: ../../../site/static/icon/oracle.png
maintainer_github: coder
verified: true
tags: [vm, linux, oracle, oci]
---

# Remote Development on Oracle Cloud VMs (Linux)

Provision Oracle Cloud Infrastructure (OCI) Linux VMs as [Coder workspaces](https://coder.com/docs/v2/latest/workspaces) with this example template.

## What this template gives you

- Preemptible OCI instances (`VM.Standard.E4.Flex`)
- Fixed `2` OCPUs
- Selectable memory: `16 GB` or `32 GB`
- Private IP only on workspace VNIC (`assign_public_ip = false`)
- Persistent block volume mounted at `/home/<username>`

## Prerequisites

### Authentication

Use API key auth for the simplest setup. Configure credentials for the same OS user that runs `coderd`.

#### Option A (recommended): API key auth

1. Create (or choose) an OCI user for Coder template provisioning.
2. Add the user to a group (for example, `coder-provisioners`).
3. Create IAM policies in your tenancy for the target compartment:

   ```text
   Allow group coder-provisioners to manage instance-family in compartment <compartment-name>
   Allow group coder-provisioners to manage volume-family in compartment <compartment-name>
   Allow group coder-provisioners to manage virtual-network-family in compartment <compartment-name>
   Allow group coder-provisioners to read instance-images in tenancy
   ```

4. Generate an API key pair on the `coderd` host:

   ```sh
   mkdir -p ~/.oci
   openssl genrsa -out ~/.oci/coder_api_key.pem 2048
   chmod 600 ~/.oci/coder_api_key.pem
   openssl rsa -pubout -in ~/.oci/coder_api_key.pem -out ~/.oci/coder_api_key_public.pem
   ```

5. In OCI Console, open your user, add an API key, and upload `~/.oci/coder_api_key_public.pem`.
6. Collect these values from OCI:
   - `tenancy_ocid`
   - `user_ocid`
   - API key `fingerprint`
   - `region` (for example `ap-mumbai-1`)
7. Create `~/.oci/config`:

   ```ini
   [DEFAULT]
   user=<user_ocid>
   fingerprint=<api_key_fingerprint>
   tenancy=<tenancy_ocid>
   region=ap-mumbai-1
   key_file=/home/<coderd-user>/.oci/coder_api_key.pem
   ```

8. If `coderd` runs as a system service, ensure this file/key are readable by that service user and restart `coderd`.

#### Option B: OCI CLI-assisted setup

If you prefer guided setup, run `oci setup config` as the `coderd` OS user. It creates the same `~/.oci/config` format used by the Terraform OCI provider.

```sh
oci setup config
```

Terraform provider docs:
- https://registry.terraform.io/providers/oracle/oci/latest/docs

### Required values at workspace creation

- `compartment_ocid`
- `availability_domain`
- `subnet_ocid` (shared subnet in your pre-created shared VCN)
- `region` (defaults to `ap-mumbai-1`)

Quick way to get availability domains with OCI CLI:

```sh
oci iam availability-domain list --compartment-id <tenancy_ocid> --query 'data[].name' --raw-output
```

If you use OCI Console instead, open your compartment details for `compartment_ocid`, and use the Compute launch form or AD list for `availability_domain`.

Quick way to list subnets and copy the `subnet_ocid` value:

```sh
oci network subnet list --compartment-id <compartment_ocid> --all --query 'data[].{"name":"display-name","subnet_ocid":id}'
```

## Architecture

This template assumes you have a shared OCI network already created (for example, one VCN and one subnet with the required outbound path) and provisions the following per workspace:

- OCI preemptible VM (`VM.Standard.E4.Flex`, `2` OCPUs, `16/32` GB RAM)
- Persistent OCI block volume for home directory

When a workspace stops, the VM is recreated on next start, while the home volume is preserved. Network resources are shared across workspaces and are not created by this template.

## Networking FAQ

### Can I use a public IP and remove the internet gateway?

Public IP and IGW are a pair. A public IP alone is not enough, and IGW without public IPs does not provide internet to private-only instances.

This template uses private IP only (`assign_public_ip = false`) and expects your shared subnet design to provide required egress.

### Private IP workspaces: how do they reach the internet?

For outbound internet from private IP instances, use a NAT Gateway path (or another outbound path such as proxy/private mirror). IGW alone is not enough for private-only VNICs.

If you do not provide outbound access, internet-dependent startup steps (apt/package downloads) will fail.

### Do I need a NAT Gateway if I already use public IPs on workspace VMs?

No. If workspace VMs have public IPs and the subnet route table sends `0.0.0.0/0` to an Internet Gateway, a NAT Gateway is not required.

Use a NAT Gateway only when you want private subnets (no public IP on VMs) while still allowing outbound internet access.

### Should I create a VCN/subnet per workspace?

For small experiments, per-workspace networking works. For real usage, it scales poorly because every workspace creates extra network resources.

Recommended pattern for Coder:
- one shared VCN per environment/region
- one or a few shared subnets for workspace VMs
- one shared Internet Gateway (public subnet model) or one shared NAT Gateway (private subnet model)

### One gateway per workspace or one for all?

Gateways are VCN-level resources. If workspaces share one VCN, they should share the same gateway(s). If you create one VCN per workspace, each VCN needs its own gateway resources.

> **Note**
> This template is designed to be a starting point. Edit the Terraform to fit your networking, security, and image requirements.
