terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    oci = {
      source  = "oracle/oci"
      version = "~> 8.0"
    }
  }
}

data "coder_parameter" "region" {
  name         = "region"
  display_name = "Region"
  description  = "What OCI region should your workspace live in?"
  default      = "ap-hyderabad-1"
  icon         = "/emojis/1f310.png"
  mutable      = false

  option {
    name  = "India South (Hyderabad)"
    value = "ap-hyderabad-1"
    icon  = "/emojis/1f1ee-1f1f3.png"
  }

  option {
    name  = "Singapore"
    value = "ap-singapore-1"
    icon  = "/emojis/1f1f8-1f1ec.png"
  }
}

variable "compartment_ocid" {
  type        = string
  description = "OCI compartment OCID where workspace resources are created"
  default     = "ocid1.tenancy.oc1..aaaaaaaaejdfnvtpkhvnyy7lqoyuyufuziyd6mkq3xnqel6gcyg23zaa5fka" # REPLACE WITH YOUR COMPARTMENT OCID
}

variable "availability_domain" {
  type        = string
  description = "OCI availability domain (for example: Uocm:AP-MUMBAI-1-AD-1)"
  default     = "CmeG:AP-HYDERABAD-1-AD-1" # REPLACE WITH YOUR AD
}

variable "subnet_ocid" {
  type        = string
  description = "Shared subnet OCID where workspace VNICs will be attached"
  default     = "ocid1.subnet.oc1.ap-hyderabad-1.aaaaaaaa7hlro6i6feyphah4fxa3dhjrcugvemd4diu7nex5b5jjne4ntzfq" # REPLACE WITH YOUR SUBNET OCID
}

data "coder_parameter" "workspace_memory_gb" {
  name         = "workspace_memory_gb"
  display_name = "Workspace memory"
  description  = "Select memory size for VM.Standard.E4.Flex with 2 OCPUs"
  default      = "16"
  icon         = "/icon/oracle.png"
  mutable      = false

  option {
    name  = "16 GB (2 OCPU)"
    value = "16"
  }

  option {
    name  = "32 GB (2 OCPU)"
    value = "32"
  }
}

data "coder_parameter" "home_size" {
  name         = "home_size"
  display_name = "Home volume size"
  description  = "How large would you like your home volume to be (in GB)?"
  default      = 100
  type         = "number"
  icon         = "/icon/oracle.png"
  mutable      = false

  validation {
    min = 50
    max = 300
  }
}

provider "oci" {
  region = data.coder_parameter.region.value
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

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
  prefix = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"

  agent_init_script = <<-EOT
    #!/usr/bin/env sh
    set -eux

    waitonexit() {
      code=$?
      if [ "$code" -ne 0 ]; then
        echo "=== Agent script exited with non-zero code ($code). Sleeping 24h to preserve logs..."
        sleep 86400
      fi
    }
    trap waitonexit EXIT

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

  userdata = templatefile("cloud-config.yaml.tftpl", {
    username    = data.coder_workspace_owner.me.name
    init_script = base64encode(local.agent_init_script)
    hostname    = lower(data.coder_workspace.me.name)
  })
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.E4.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_volume" "home" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = "${local.prefix}-home"
  size_in_gbs         = tonumber(data.coder_parameter.home_size.value)

  freeform_tags = {
    Coder_Provisioned = "true"
  }
}

resource "oci_core_instance" "main" {
  count = data.coder_workspace.me.transition == "start" ? 1 : 0

  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = "${local.prefix}-vm"
  shape               = "VM.Standard.E4.Flex"

  shape_config {
    ocpus         = 2
    memory_in_gbs = tonumber(data.coder_parameter.workspace_memory_gb.value)
  }

  preemptible_instance_config {
    preemption_action {
      type                 = "TERMINATE"
      preserve_boot_volume = false
    }
  }

  create_vnic_details {
    subnet_id        = var.subnet_ocid
    assign_public_ip = false
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = 50
  }

  metadata = {
    user_data = base64encode(local.userdata)
  }

  freeform_tags = {
    Coder_Provisioned = "true"
  }
}

resource "oci_core_volume_attachment" "home" {
  count = data.coder_workspace.me.transition == "start" ? 1 : 0

  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.main[0].id
  volume_id       = oci_core_volume.home.id
  device          = "/dev/oracleoci/oraclevdb"
  is_read_only    = false
  is_shareable    = false
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = oci_core_instance.main[0].id

  item {
    key   = "type"
    value = oci_core_instance.main[0].shape
  }

  item {
    key   = "ocpu"
    value = "2"
  }

  item {
    key   = "memory"
    value = "${data.coder_parameter.workspace_memory_gb.value} GiB"
  }
}

resource "coder_metadata" "home_info" {
  resource_id = oci_core_volume.home.id

  item {
    key   = "size"
    value = "${data.coder_parameter.home_size.value} GiB"
  }
}
