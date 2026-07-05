terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

provider "coder" {
}

variable "kubeconfig_path" {
  type        = string
  description = "Kubeconfig path inside the Coder provisioner container. Set to an empty string to use in-cluster Kubernetes credentials."
  default     = "/home/coder/.kube/config"
}

variable "storage_class_name" {
  type        = string
  description = "Kubernetes StorageClass for workspace home PVCs."
  default     = "ssd-large"
}

variable "workspace_image" {
  type        = string
  description = "Container image to run for preview workspaces."
  default     = "codercom/enterprise-base:ubuntu-noble"
}

variable "runtime_class_name" {
  type        = string
  description = "Kubernetes RuntimeClass used for Sysbox-backed workspace pods."
  default     = "sysbox-runc"
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "CPU limit for the preview workspace pod."
  default      = "4"
  icon         = "/icon/memory.svg"
  mutable      = true

  option {
    name  = "4 Cores"
    value = "4"
  }

  option {
    name  = "8 Cores"
    value = "8"
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory"
  description  = "Memory limit for the preview workspace pod."
  default      = "8"
  icon         = "/icon/memory.svg"
  mutable      = true

  option {
    name  = "8 GiB"
    value = "8"
  }

  option {
    name  = "16 GiB"
    value = "16"
  }
}

data "coder_parameter" "home_disk_size" {
  name         = "home_disk_size"
  display_name = "Home disk size"
  description  = "Persistent home volume size, in GiB."
  default      = "50"
  type         = "number"
  icon         = "/emojis/1f4be.png"
  mutable      = false

  validation {
    min = 1
    max = 99999
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path != "" ? pathexpand(var.kubeconfig_path) : null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  namespace      = "preview"
  workspace_name = "coder-${data.coder_workspace.me.id}"
  workspace_user = data.coder_workspace_owner.me.name
  home_path      = "/home/${local.workspace_user}"

  selector_labels = {
    "app.kubernetes.io/name"     = "coder-preview-workspace"
    "app.kubernetes.io/instance" = local.workspace_name
    "app.kubernetes.io/part-of"  = "coder"
  }

  coder_labels = {
    "com.coder.resource"       = "true"
    "com.coder.workspace.id"   = data.coder_workspace.me.id
    "com.coder.workspace.name" = data.coder_workspace.me.name
    "com.coder.user.id"        = data.coder_workspace_owner.me.id
    "com.coder.user.username"  = data.coder_workspace_owner.me.name
    "com.coder.preview"        = "true"
  }

  workspace_labels = merge(local.selector_labels, local.coder_labels)
  pvc_labels = merge(local.coder_labels, {
    "app.kubernetes.io/name"     = "coder-preview-pvc"
    "app.kubernetes.io/instance" = "${local.workspace_name}-home"
    "app.kubernetes.io/part-of"  = "coder"
  })

  annotations = {
    "com.coder.user.email" = data.coder_workspace_owner.me.email
  }

  preview_apps = {
    portal = {
      display_name     = "Portal"
      port             = 1338
      path             = "/"
      healthcheck_path = "/__/env.json"
      order            = 2
    }
    touchless = {
      display_name     = "Touchless"
      port             = 1339
      path             = "/"
      healthcheck_path = "/__/env.json"
      order            = 3
    }
    server = {
      display_name     = "Server"
      port             = 1337
      path             = "/"
      healthcheck_path = "/vms/health"
      order            = 4
    }
    "live-query" = {
      display_name     = "LiveQuery"
      port             = 1334
      path             = "/health"
      healthcheck_path = "/health"
      order            = 5
    }
    temporal = {
      display_name     = "Temporal UI"
      port             = 8233
      path             = "/"
      healthcheck_path = "/"
      order            = 6
    }
    sendria = {
      display_name     = "Sendria"
      port             = 1080
      path             = "/"
      healthcheck_path = "/"
      order            = 7
    }
    "parse-dashboard" = {
      display_name     = "Parse Dashboard"
      port             = 4040
      path             = "/"
      healthcheck_path = "/"
      order            = 8
    }
    shlink = {
      display_name     = "Shlink"
      port             = 1335
      path             = "/"
      healthcheck_path = "/l/rest/health"
      order            = 9
    }
  }
}

resource "coder_agent" "main" {
  arch           = "amd64"
  os             = "linux"
  startup_script = <<-EOT
    #!/usr/bin/env sh
    set -eu

    if command -v apt-get >/dev/null 2>&1; then
      if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        export DEBIAN_FRONTEND=noninteractive

        while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
          echo "Waiting for other software managers to finish..."
          sleep 2
        done

        sudo apt-get update
        sudo NEEDRESTART_MODE=a DEBIAN_FRONTEND=noninteractive apt-get -y install \
          apt-transport-https \
          build-essential \
          ca-certificates \
          curl \
          git \
          gnupg \
          jq \
          libcairo2-dev \
          libgif-dev \
          libjpeg-dev \
          libpango1.0-dev \
          librsvg2-dev \
          lsb-release \
          pkg-config \
          unzip \
          wget

        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -

        sudo mkdir -p -m 755 /etc/apt/keyrings
        wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
        sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null

        wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

        sudo apt-get update
        sudo NEEDRESTART_MODE=a DEBIAN_FRONTEND=noninteractive apt-get -y install \
          containerd.io \
          docker-ce \
          docker-ce-cli \
          docker-compose-plugin \
          gh \
          nodejs \
          vault
      else
        echo "Passwordless sudo is unavailable; skipping apt package bootstrap."
      fi
    else
      echo "apt-get is unavailable; skipping Ubuntu package bootstrap."
    fi

    touch "$HOME/.bashrc"
    mkdir -p "$HOME/.local/bin" "$HOME/.npm-global"

    if command -v npm >/dev/null 2>&1; then
      npm config set prefix "$HOME/.npm-global"
      export NPM_CONFIG_PREFIX="$HOME/.npm-global"
      export PATH="$PATH:$HOME/.npm-global/bin"
      grep -Fqx 'export NPM_CONFIG_PREFIX="$HOME/.npm-global"' "$HOME/.bashrc" || echo 'export NPM_CONFIG_PREFIX="$HOME/.npm-global"' >>"$HOME/.bashrc"
      grep -Fqx 'export PATH="$PATH:$HOME/.npm-global/bin"' "$HOME/.bashrc" || echo 'export PATH="$PATH:$HOME/.npm-global/bin"' >>"$HOME/.bashrc"

      if ! command -v pnpm >/dev/null 2>&1; then
        npm install -g pnpm
      fi
    fi

    if ! command -v starship >/dev/null 2>&1; then
      curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
    fi
    grep -Fqx 'export PATH="$PATH:$HOME/.local/bin"' "$HOME/.bashrc" || echo 'export PATH="$PATH:$HOME/.local/bin"' >>"$HOME/.bashrc"
    grep -Fqx 'eval "$(starship init bash)"' "$HOME/.bashrc" || echo 'eval "$(starship init bash)"' >>"$HOME/.bashrc"

    if [ ! -x "$HOME/.temporalio/bin/temporal" ]; then
      curl -sSf https://temporal.download/cli.sh | sh -s -- --dir "$HOME/.temporalio"
    fi
    grep -Fqx 'export PATH="$PATH:$HOME/.temporalio/bin"' "$HOME/.bashrc" || echo 'export PATH="$PATH:$HOME/.temporalio/bin"' >>"$HOME/.bashrc"

    if command -v dockerd >/dev/null 2>&1 && ! pgrep -x dockerd >/dev/null 2>&1; then
      mkdir -p "$HOME/.docker-data" "$HOME/.containerd-data"
      sudo dockerd --data-root "$HOME/.docker-data" >"/tmp/dockerd.log" 2>&1 &
    fi

    CODE_SERVER_PREFIX="/tmp/code-server"
    if [ ! -x "$CODE_SERVER_PREFIX/bin/code-server" ]; then
      curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix="$CODE_SERVER_PREFIX"
    fi
    "$CODE_SERVER_PREFIX/bin/code-server" --auth none --port 13337 >"/tmp/code-server.log" 2>&1 &

    cd "$HOME"
    if [ -x "$HOME/.preview/start.sh" ]; then
      nohup "$HOME/.preview/start.sh" >"$HOME/.preview/start.log" 2>&1 &
    else
      echo "No preview start script found at $HOME/.preview/start.sh"
    fi
  EOT

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    script       = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval     = 60
    timeout      = 1
  }
}

resource "coder_app" "code_server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337/?folder=${local.home_path}"
  subdomain    = false
  share        = "owner"
  order        = 1

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 12
  }
}

resource "coder_app" "preview" {
  for_each = local.preview_apps

  agent_id     = coder_agent.main.id
  slug         = each.key
  display_name = each.value.display_name
  url          = "http://localhost:${each.value.port}${each.value.path}"
  subdomain    = true
  share        = "authenticated"
  order        = each.value.order

  healthcheck {
    url       = "http://localhost:${each.value.port}${each.value.healthcheck_path}"
    interval  = 5
    threshold = 12
  }
}

resource "kubernetes_persistent_volume_claim_v1" "home" {
  metadata {
    name        = "${local.workspace_name}-home"
    namespace   = local.namespace
    labels      = local.pvc_labels
    annotations = local.annotations
  }

  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class_name

    resources {
      requests = {
        storage = "${data.coder_parameter.home_disk_size.value}Gi"
      }
    }
  }
}

resource "kubernetes_manifest" "main" {
  count = data.coder_workspace.me.start_count

  depends_on = [
    kubernetes_persistent_volume_claim_v1.home
  ]

  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name        = local.workspace_name
      namespace   = local.namespace
      labels      = local.workspace_labels
      annotations = local.annotations
    }
    spec = {
      replicas = 1
      selector = {
        matchLabels = local.selector_labels
      }
      strategy = {
        type = "Recreate"
      }
      template = {
        metadata = {
          labels      = local.workspace_labels
          annotations = local.annotations
        }
        spec = {
          runtimeClassName = var.runtime_class_name
          hostUsers        = false
          securityContext = {
            runAsUser = 0
            fsGroup   = 1000
          }
          containers = [
            {
              name            = "dev"
              image           = var.workspace_image
              imagePullPolicy = "IfNotPresent"
              command = ["sh", "-c", <<-EOT
            set -eu

            if ! getent group sudo >/dev/null 2>&1; then
              groupadd sudo
            fi

            if ! getent group docker >/dev/null 2>&1; then
              groupadd docker
            fi

            if id -u "$WORKSPACE_USER" >/dev/null 2>&1; then
              usermod -d "$HOME" "$WORKSPACE_USER"
            elif id -u coder >/dev/null 2>&1; then
              if getent group coder >/dev/null 2>&1 && ! getent group "$WORKSPACE_USER" >/dev/null 2>&1; then
                groupmod -n "$WORKSPACE_USER" coder
              fi
              usermod -l "$WORKSPACE_USER" -d "$HOME" coder
            else
              if ! getent group "$WORKSPACE_USER" >/dev/null 2>&1; then
                groupadd --gid 1000 "$WORKSPACE_USER" 2>/dev/null || groupadd "$WORKSPACE_USER"
              fi
              useradd --uid 1000 --gid "$WORKSPACE_USER" --home-dir "$HOME" --shell /bin/bash "$WORKSPACE_USER" 2>/dev/null || \
                useradd --gid "$WORKSPACE_USER" --home-dir "$HOME" --shell /bin/bash "$WORKSPACE_USER"
            fi

            usermod -aG sudo,docker "$WORKSPACE_USER"
            mkdir -p "$HOME"
            chown -R "$WORKSPACE_USER:$WORKSPACE_USER" "$HOME"
            printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$WORKSPACE_USER" >/etc/sudoers.d/coder-workspace-user
            chmod 0440 /etc/sudoers.d/coder-workspace-user

            cat >/tmp/coder-agent-init <<'CODER_AGENT_INIT'
            ${coder_agent.main.init_script}
            CODER_AGENT_INIT
            chown "$WORKSPACE_USER:$WORKSPACE_USER" /tmp/coder-agent-init
            chmod 0755 /tmp/coder-agent-init

            if command -v sudo >/dev/null 2>&1; then
              exec sudo -E -H -u "$WORKSPACE_USER" env HOME="$HOME" USER="$WORKSPACE_USER" LOGNAME="$WORKSPACE_USER" /bin/sh /tmp/coder-agent-init
            fi
            exec runuser -u "$WORKSPACE_USER" -- env HOME="$HOME" USER="$WORKSPACE_USER" LOGNAME="$WORKSPACE_USER" /bin/sh /tmp/coder-agent-init
          EOT
              ]
              securityContext = {
                runAsUser = 0
              }
              env = [
                {
                  name  = "CODER_AGENT_TOKEN"
                  value = coder_agent.main.token
                },
                {
                  name  = "WORKSPACE_USER"
                  value = local.workspace_user
                },
                {
                  name  = "HOME"
                  value = local.home_path
                }
              ]
              resources = {
                requests = {
                  cpu    = "2"
                  memory = "4Gi"
                }
                limits = {
                  cpu    = data.coder_parameter.cpu.value
                  memory = "${data.coder_parameter.memory.value}Gi"
                }
              }
              volumeMounts = [
                {
                  mountPath = local.home_path
                  name      = "home"
                }
              ]
            }
          ]
          volumes = [
            {
              name = "home"
              persistentVolumeClaim = {
                claimName = kubernetes_persistent_volume_claim_v1.home.metadata.0.name
              }
            }
          ]
          affinity = {
            podAntiAffinity = {
              preferredDuringSchedulingIgnoredDuringExecution = [
                {
                  weight = 1
                  podAffinityTerm = {
                    topologyKey = "kubernetes.io/hostname"
                    labelSelector = {
                      matchExpressions = [
                        {
                          key      = "app.kubernetes.io/name"
                          operator = "In"
                          values   = ["coder-preview-workspace"]
                        }
                      ]
                    }
                  }
                }
              ]
            }
          }
        }
      }
    }
  }
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = coder_agent.main.id

  item {
    key   = "namespace"
    value = local.namespace
  }

  item {
    key   = "image"
    value = var.workspace_image
  }

  item {
    key   = "cpu"
    value = "${data.coder_parameter.cpu.value} cores"
  }

  item {
    key   = "memory"
    value = "${data.coder_parameter.memory.value} GiB"
  }
}

resource "coder_metadata" "home_info" {
  resource_id = kubernetes_persistent_volume_claim_v1.home.id

  item {
    key   = "size"
    value = "${data.coder_parameter.home_disk_size.value} GiB"
  }
}
