terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.60"
    }
  }
}

data "coder_parameter" "instance_type" {
  name         = "instance_type"
  display_name = "Instance type"
  description  = "Which Hetzner Cloud server type should your workspace use?"
  default      = "cx43"
  icon         = "/emojis/2601-fe0f.png"
  mutable      = false

  option {
    name  = "cx43 (8 vCPU, 16 GiB RAM)"
    value = "cx43"
  }

  option {
    name  = "cx53 (16 vCPU, 32 GiB RAM)"
    value = "cx53"
  }
}

provider "hcloud" {}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "hcloud_server_type" "selected" {
  name = data.coder_parameter.instance_type.value
}

check "selected_server_type_available_in_fsn1" {
  assert {
    condition = contains(
      [for location in data.hcloud_server_type.selected.locations : location.name],
      local.location,
    )
    error_message = "Selected Hetzner server type ${data.hcloud_server_type.selected.name} is not available in ${local.location}."
  }
}

resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"

  metadata {
    key          = "cpu"
    display_name = "CPU Usage"
    interval     = 5
    timeout      = 5
    script       = <<-EOT
      #!/bin/bash
      set -e
      top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4 "%"}'
    EOT
  }

  metadata {
    key          = "memory"
    display_name = "Memory Usage"
    interval     = 5
    timeout      = 5
    script       = <<-EOT
      #!/bin/bash
      set -e
      free -m | awk 'NR==2{printf "%.2f%%\t", $3*100/$2 }'
    EOT
  }

  metadata {
    key          = "disk"
    display_name = "Disk Usage"
    interval     = 600
    timeout      = 30
    script       = <<-EOT
      #!/bin/bash
      set -e
      df /home/${data.coder_workspace_owner.me.name} | awk 'NR==2{printf "%s", $5}'
    EOT
  }
}

module "code-server" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/code-server/coder"
  version = "~> 1.0"

  agent_id = coder_agent.main.id
  order    = 1
}

locals {
  location            = "fsn1"
  home_volume_size_gb = 100
  raw_name            = lower("coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}")
  sanitized_name      = trim(replace(local.raw_name, "/[^a-z0-9-]/", "-"), "-")
  base_name           = trimsuffix(substr(local.sanitized_name != "" ? local.sanitized_name : "coder-workspace", 0, 58), "-")
  server_name         = local.base_name
  volume_name         = "${local.base_name}-home"

  agent_init_script = <<-EOT
    #!/usr/bin/env sh
    set -eux

    BINARY_DIR="$(mktemp -d -t coder.XXXXXX)"
    BINARY_NAME="coder"
    BINARY_URL="${trimsuffix(data.coder_workspace.me.access_url, "/")}/bin/coder-linux-amd64"
    cd "$BINARY_DIR"

    while :; do
      status=""
      if command -v curl >/dev/null 2>&1; then
        curl -fsSL --compressed "$BINARY_URL" -o "$BINARY_NAME" && break
        status=$?
      elif command -v wget >/dev/null 2>&1; then
        wget -q "$BINARY_URL" -O "$BINARY_NAME" && break
        status=$?
      elif command -v busybox >/dev/null 2>&1; then
        busybox wget -q "$BINARY_URL" -O "$BINARY_NAME" && break
        status=$?
      else
        echo "error: no download tool found, please install curl, wget or busybox wget"
        exit 127
      fi

      echo "error: failed to download coder agent"
      echo "       command returned: $status"
      echo "Trying again in 30 seconds..."
      sleep 30
    done

    chmod +x "./$BINARY_NAME"

    export CODER_AGENT_AUTH="token"
    export CODER_AGENT_TOKEN="${coder_agent.main.token}"
    export CODER_AGENT_URL="${trimsuffix(data.coder_workspace.me.access_url, "/")}"

    output="$(./$BINARY_NAME --version | head -n1)"
    if ! echo "$output" | grep -q Coder; then
      echo >&2 "ERROR: Downloaded agent binary returned unexpected version output"
      echo >&2 "$BINARY_NAME --version output: \"$output\""
      exit 2
    fi

    exec "./$BINARY_NAME" agent
  EOT

  userdata = templatefile("${path.module}/cloud-config.yaml.tftpl", {
    username           = data.coder_workspace_owner.me.name
    init_script        = base64encode(local.agent_init_script)
    hostname           = local.server_name
    home_volume_device = hcloud_volume.home.linux_device
  })
}

resource "hcloud_volume" "home" {
  name     = local.volume_name
  location = local.location
  size     = local.home_volume_size_gb

  labels = {
    coder_provisioned = "true"
    coder_workspace   = "true"
  }
}

resource "hcloud_server" "main" {
  count = data.coder_workspace.me.transition == "start" ? 1 : 0

  name        = local.server_name
  location    = local.location
  image       = "ubuntu-24.04"
  server_type = data.hcloud_server_type.selected.name
  ssh_keys    = ["hetzner"]
  user_data   = local.userdata

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  labels = {
    coder_provisioned = "true"
    coder_workspace   = "true"
  }

  lifecycle {
    ignore_changes = [ssh_keys]
  }
}

resource "hcloud_volume_attachment" "home" {
  count = data.coder_workspace.me.transition == "start" ? 1 : 0

  volume_id = hcloud_volume.home.id
  server_id = hcloud_server.main[0].id
  automount = false
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = tostring(hcloud_server.main[0].id)

  item {
    key   = "type"
    value = data.hcloud_server_type.selected.name
  }

  item {
    key   = "cores"
    value = tostring(data.hcloud_server_type.selected.cores)
  }

  item {
    key   = "memory"
    value = "${data.hcloud_server_type.selected.memory} GiB"
  }
}

resource "coder_metadata" "home_info" {
  resource_id = tostring(hcloud_volume.home.id)

  item {
    key   = "size"
    value = "${local.home_volume_size_gb} GiB"
  }
}
