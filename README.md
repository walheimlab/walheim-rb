# Walheim

[![Gem Version](https://img.shields.io/gem/v/walheim)](https://rubygems.org/gems/walheim)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/walheimlab/walheim-rb)

A kubectl-style CLI for managing Docker-based homelab infrastructure across multiple machines.

## Overview

Walheim provides a familiar Kubernetes-like interface for deploying and managing applications in your homelab. Use `whctl` (Walheim Control) to manage namespaces, apps, secrets, and configuration across your physical machines.

**Key Features:**
- kubectl-style CLI interface (`whctl get`, `whctl apply`, `whctl exec`, etc.)
- Context-based configuration for multiple environments
- Docker Compose as the application definition format
- Kubernetes-style Secret and ConfigMap management with automatic injection
- SSH-based deployment to remote machines
- Container status tracking across all namespaces
- Namespace = physical machine mapping
- Advanced environment variable management with precedence rules

## Installation

```bash
gem install walheim
```

## Quick Start

### 1. Create Your First Context

A context points to a data directory containing your homelab configuration:

```bash
# Create a context for your homelab
whctl context new homelab --data-dir ~/my-homelab

# The data directory will be created if it doesn't exist
```

### 2. Create a Namespace

Namespaces in Walheim represent physical machines:

```bash
# Create a namespace for a production server
whctl create namespace production \
  --hostname prod.example.com \
  --username admin
```

### 3. Deploy an Application

```bash
# Import an existing docker-compose.yml
whctl import app nginx -n production -f docker-compose.yml

# Deploy the app to the namespace
whctl apply app nginx -n production
```

## Context Management

Walheim uses contexts to manage multiple homelab environments (similar to kubectl):

```bash
# Create contexts for different environments
whctl context new homelab --data-dir ~/homelab-prod
whctl context new staging --data-dir ~/homelab-staging

# List all contexts (* indicates active)
whctl context list
# CURRENT   NAME       DATA DIRECTORY
# *         homelab    /home/user/homelab-prod
#           staging    /home/user/homelab-staging

# Switch between contexts
whctl context use staging

# Show current context
whctl context current
# Current context: staging
# Data directory: /home/user/homelab-staging

# Delete a context
whctl context delete old-context

# Override context for a single command
whctl --context homelab get namespaces
```

Configuration is stored in `~/.walheim/config`:

```yaml
apiVersion: walheim.io/v1
kind: Config
currentContext: homelab
contexts:
  - name: homelab
    dataDir: /home/user/homelab-prod
  - name: staging
    dataDir: /home/user/homelab-staging
```

## Common Commands

### Namespace Management

```bash
# List all namespaces (can use 'ns' alias)
whctl get namespaces
whctl get ns

# Create a namespace (represents a physical machine)
whctl create namespace production \
  --hostname prod.example.com \
  --username admin

# Show detailed namespace information
whctl describe namespace production
# Shows: SSH status, Docker version, deployed apps, resource counts, disk usage
```

### Application Management

```bash
# List apps in a namespace
whctl get apps -n production

# List apps across all namespaces (shows status and ready count)
whctl get apps --all
# STATUS: Running, Stopped, Degraded, Paused, NotFound
# READY: X/Y (running containers / total containers)

# Deploy an app
whctl apply app myapp -n production

# Import from docker-compose.yml (converts to Walheim App format)
whctl import app myapp -n production -f docker-compose.yml

# Start/pause/stop an app
whctl start app myapp -n production
whctl pause app myapp -n production   # Stop containers, keep files
whctl stop app myapp -n production    # Stop and remove files from remote

# Pull latest images without restarting
whctl pull app myapp -n production

# Show detailed running status (docker ps + stats)
whctl describe app myapp -n production

# Execute commands in app containers
whctl exec app myapp -n production -- ls -la
whctl exec app myapp -n production -s myservice -- bash
whctl exec app myapp -n production -it -- /bin/sh  # Interactive shell

# View logs
whctl logs app myapp -n production
whctl logs app myapp -n production --follow
whctl logs app myapp -n production --tail 100
whctl logs app myapp -n production --timestamps
```

### Secret Management

```bash
# List secrets
whctl get secrets -n production
whctl get secrets --all  # All namespaces

# Deploy a secret
whctl apply secret db-creds -n production

# Create from file
whctl apply secret db-creds -n production -f secret.yaml

# Delete a secret
whctl delete secret db-creds -n production

# Secrets are automatically injected via spec.envFrom in App manifest
```

### ConfigMap Management

```bash
# List configmaps (can use 'cm' alias)
whctl get configmaps -n production
whctl get cm --all  # All namespaces

# Deploy a configmap
whctl apply configmap app-config -n production

# Create from file
whctl apply cm app-config -n production -f configmap.yaml

# Delete a configmap
whctl delete cm app-config -n production

# ConfigMaps are injected via spec.envFrom in App manifest
```

## Data Directory Structure

Your homelab configuration lives in a data directory:

```
~/my-homelab/
└── namespaces/
    ├── production/
    │   ├── .namespace.yaml      # SSH credentials
    │   ├── apps/
    │   │   ├── nginx/
    │   │   │   ├── .app.yaml           # Walheim App manifest
    │   │   │   └── docker-compose.yml  # Generated (do not edit)
    │   │   └── postgres/
    │   │       ├── .app.yaml
    │   │       └── docker-compose.yml
    │   ├── secrets/
    │   │   └── db-creds/
    │   │       └── .secret.yaml
    │   └── configmaps/
    │       └── app-config/
    │           └── configmap.yaml
    └── staging/
        ├── .namespace.yaml
        ├── apps/
        │   └── myapp/
        │       ├── .app.yaml
        │       └── docker-compose.yml
        ├── secrets/
        └── configmaps/
```

### Namespace Configuration

Each namespace has a `.namespace.yaml` file with SSH connection details:

```yaml
username: admin
hostname: production.example.com
```

### Walheim App Manifest

Apps use a Walheim-specific manifest format (`.app.yaml`):

```yaml
apiVersion: walheim/v1alpha1
kind: App
metadata:
  name: myapp
  namespace: production
spec:
  # Your docker-compose configuration
  compose:
    services:
      web:
        image: myapp:latest
        ports:
          - "8080:8080"
        environment:
          APP_MODE: production  # Existing env vars have highest precedence

  # Optional: Inject from secrets/configmaps (lower precedence)
  envFrom:
    - secretRef:
        name: db-creds
      # Optional: target specific services only
      # serviceNames: [web]
    - configMapRef:
        name: app-config

  # Optional: Direct env vars with variable substitution (medium precedence)
  env:
    - name: DATABASE_URL
      value: "postgres://user:${DB_PASSWORD}@localhost/mydb"
      # Optional: target specific services
      # serviceNames: [web]
```

**Environment Variable Precedence** (highest to lowest):
1. Existing `environment` in docker-compose spec
2. `spec.env[]` - Direct environment variables
3. `spec.envFrom[]` - Injected from secrets/configmaps

**Generated docker-compose.yml:**
When you run `whctl apply app`, Walheim generates the final `docker-compose.yml`:

```yaml
services:
  web:
    image: myapp:latest
    ports:
      - "8080:8080"
    labels:
      - walheim.managed=true
      - walheim.namespace=production
      - walheim.app=myapp
      - walheim.injected-env.secret.db-creds=DB_PASSWORD,API_KEY
      - walheim.injected-env.configmap.app-config=LOG_LEVEL
      - walheim.injected-env.override=DATABASE_URL
    environment:
      APP_MODE: production
      DB_PASSWORD: secret123        # From secret
      API_KEY: abc-xyz              # From secret
      LOG_LEVEL: info               # From configmap
      DATABASE_URL: postgres://user:secret123@localhost/mydb  # From spec.env with substitution
```

### Secret Format

Secrets use Kubernetes-style YAML format:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-creds
  namespace: production
type: Opaque
stringData:
  DB_PASSWORD: "secret123"
  API_KEY: "abc-xyz"
data:
  # Can also use base64-encoded data
  CERTIFICATE: "LS0tLS1CRUdJTi..."
```

### ConfigMap Format

ConfigMaps use Kubernetes-style YAML format:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: production
data:
  LOG_LEVEL: "info"
  MAX_CONNECTIONS: "100"
  FEATURE_FLAGS: "feature1,feature2"
```

## Architecture

### Namespaces vs Nodes

Unlike Kubernetes where namespaces are logical and nodes are physical:

- **Walheim namespace = physical machine** (1:1 mapping)
- No scheduling - you explicitly target a namespace with `-n`
- Each namespace has its own SSH credentials

### Deployment Flow

1. You maintain configuration in your data directory (Git repository)
2. Edit `.app.yaml` manifest with compose spec, secrets, and env vars
3. Run `whctl apply app myapp -n production`
4. Walheim generates final `docker-compose.yml` with:
   - Injected environment variables from secrets/configmaps
   - Automatic metadata labels for tracking
   - Variable substitution in env values
5. Syncs files to remote machine via rsync/SSH
6. Runs `docker compose up -d` on the remote machine

### Container Metadata

Walheim automatically adds labels to all managed containers:

```yaml
labels:
  - walheim.managed=true              # Marks container as Walheim-managed
  - walheim.namespace=production      # Namespace identifier
  - walheim.app=myapp                 # App name
  - walheim.injected-env.secret.db-creds=DB_PASSWORD,API_KEY  # Tracking
```

These labels enable:
- **Status tracking**: `whctl get apps --all` shows real-time container status
- **Resource filtering**: Query containers by namespace or app
- **Audit trail**: Track which secrets/configmaps were injected

### Resource Types

- **ClusterResource**: Resources at the top level (e.g., namespaces)
  - Path: `{data_dir}/namespaces/{name}/.namespace.yaml`
  - Example: `whctl get namespaces` (alias: `ns`)

- **NamespacedResource**: Resources within a namespace (e.g., apps, secrets, configmaps)
  - Apps: `{data_dir}/namespaces/{namespace}/apps/{name}/.app.yaml`
  - Secrets: `{data_dir}/namespaces/{namespace}/secrets/{name}/.secret.yaml`
  - ConfigMaps: `{data_dir}/namespaces/{namespace}/configmaps/{name}/configmap.yaml`
  - Example: `whctl get apps -n production`
  - Example: `whctl get cm --all` (alias for configmaps)

### Container Status Tracking

Walheim shows current container status across all namespaces:

```bash
$ whctl get apps --all
NAMESPACE    NAME        IMAGE                  READY  STATUS
production   nginx       nginx:latest           2/2    Running
production   postgres    postgres:15            1/1    Running
staging      myapp       myapp:dev              1/2    Degraded
staging      redis       redis:7                0/1    Stopped
```

**Status Values:**
- `Running`: All containers are running
- `Degraded`: Some containers running, some not
- `Stopped`: All containers stopped/exited
- `Paused`: Containers are paused
- `NotFound`: App deployed but no containers found
- `Unknown`: Unable to determine status

**How it works:**
- Walheim queries all hosts in parallel via SSH during `get` commands
- Containers are identified by `walheim.*` labels
- Status is aggregated from all containers in the app
- Efficient batch queries minimize SSH overhead

## kubectl Feature Parity

Walheim borrows from kubectl's UX but is intentionally scoped for Docker-based homelabs. This section documents which kubectl features are implemented, planned, or marked as WONTDO.

### Resource Operations

| Feature | Status | Notes |
|---------|--------|-------|
| `get` | ✅ Implemented | List resources with table output |
| `describe` | ✅ Implemented | Detailed resource information (namespaces, apps) |
| `apply` | ✅ Implemented | Create/update resources (apps, secrets, configmaps) |
| `create` | ✅ Implemented | Create namespaces |
| `delete` | ✅ Implemented | Delete secrets and configmaps |
| `edit` | 🚧 Planned | Interactive editing of resources |
| `patch` | 🚧 Planned | Partial resource updates |

### Filtering and Selection

| Feature | Status | Notes |
|---------|--------|-------|
| `-n, --namespace` | ✅ Implemented | Target specific namespace |
| `--all, -A` | ✅ Implemented | List across all namespaces |
| Label selectors (`-l`) | 🚧 Planned | Filter by labels (e.g., `-l app=nginx`) |
| Field selectors | 🚧 Planned | Filter by field values |

### Output Formats

| Feature | Status | Notes |
|---------|--------|-------|
| Table output | ✅ Implemented | Default output format |
| `-o yaml` | 🚧 Planned | YAML output format |
| `-o json` | 🚧 Planned | JSON output format |
| `-o wide` | 🚧 Planned | Additional columns in table output |

### Context and Configuration

| Feature | Status | Notes |
|---------|--------|-------|
| `context new` | ✅ Implemented | Create new contexts |
| `context list` | ✅ Implemented | List all contexts |
| `context use` | ✅ Implemented | Switch active context |
| `context current` | ✅ Implemented | Show current context |
| `context delete` | ✅ Implemented | Delete contexts |
| `--context` flag | ✅ Implemented | Override context for single command |
| Config file | ✅ Implemented | `~/.walheim/config` |

### Container Interaction

| Feature | Status | Notes |
|---------|--------|-------|
| `exec` | ✅ Implemented | Execute commands in containers |
| `logs` | ✅ Implemented | View container logs with `--follow`, `--tail`, `--timestamps` |
| `port-forward` | ❌ WONTDO | Use SSH tunnels instead (`ssh -L`) |
| `attach` | 🚧 Planned | Attach to running container |
| `cp` | 🚧 Planned | Copy files to/from containers |

### Application Lifecycle

| Feature | Status | Notes |
|---------|--------|-------|
| `apply` | ✅ Implemented | Deploy apps with environment injection |
| `start` | ✅ Implemented | Start stopped apps |
| `pause` | ✅ Implemented | Pause apps (stop containers, keep files) |
| `stop` | ✅ Implemented | Stop and remove apps from remote |
| `pull` | ✅ Implemented | Pull latest images without restart |
| `scale` | ❌ WONTDO | No scheduling; manually edit docker-compose replicas |
| `rollout` | ❌ WONTDO | Manual rollback via docker compose |
| `rollout history` | ❌ WONTDO | Track manually in Git commits |

### Access Control and Security

| Feature | Status | Notes |
|---------|--------|-------|
| RBAC | ❌ WONTDO | Use SSH key-based permissions per namespace |
| Service accounts | ❌ WONTDO | Use SSH users |
| Network policies | ❌ WONTDO | Configure via Docker networks and firewall rules |

### Metadata and Labels

| Feature | Status | Notes |
|---------|--------|-------|
| Automatic labels | ✅ Implemented | `walheim.managed`, `walheim.namespace`, `walheim.app` |
| Injection tracking | ✅ Implemented | `walheim.injected-env.*` labels |
| Custom metadata | ✅ Implemented | Via `metadata.labels` in manifests |
| Annotations | 🚧 Planned | Arbitrary metadata storage |

### Multi-Tenancy

| Feature | Status | Notes |
|---------|--------|-------|
| Namespace isolation | ❌ WONTDO | Namespaces = physical machines, isolated by SSH/network |
| Resource quotas | ❌ WONTDO | Manage manually via Docker resource limits |
| Limit ranges | ❌ WONTDO | Set in docker-compose directly |

### Key Differences from kubectl

**Philosophy**: Walheim is designed for homelab simplicity, not production Kubernetes orchestration.

- **No scheduler**: You explicitly target namespaces; no automatic pod placement
- **No control plane**: Each namespace is independent; no central API server
- **Physical = logical**: Namespaces map 1:1 to physical machines
- **SSH-based**: Deployment uses rsync + SSH, not kubelet
- **Git as state**: Your data directory is the source of truth (GitOps-friendly)

## Global Flags

```bash
# Override active context
whctl --context staging get namespaces

# Use alternate config file
whctl --whconfig /path/to/config get namespaces

# Or via environment variable
WHCONFIG=/path/to/config whctl get namespaces
```

## Development

### Setup

```bash
# Clone the repository
git clone https://github.com/walheimlab/walheim-rb
cd walheim-rb

# Install dependencies
bundle install

# Run locally
./bin/whctl --help
```

### Building

```bash
# Build the gem
gem build walheim.gemspec

# Install locally
gem install --local walheim-*.gem

# Test
whctl --help
```

### Testing

```bash
# Create a test context
./bin/whctl context new test --data-dir /tmp/walheim-test

# Create test resources
./bin/whctl create namespace demo --hostname localhost --username $USER

# Import a docker-compose.yml (converts to .app.yaml)
./bin/whctl import app nginx -n demo -f /path/to/docker-compose.yml

# Verify
./bin/whctl get namespaces
./bin/whctl get apps -n demo
./bin/whctl describe namespace demo
```

## For Maintainers

If you're a maintainer releasing new versions:

- **[Release Process](docs/maintainers/release.md)** - Step-by-step guide for publishing to RubyGems

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test locally
5. Submit a pull request

## License

MIT

## Links

- **Repository**: https://github.com/walheimlab/walheim-rb
- **Issues**: https://github.com/walheimlab/walheim-rb/issues
- **RubyGems**: https://rubygems.org/gems/walheim
