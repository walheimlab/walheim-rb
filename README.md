# Walheim

A kubectl-style CLI for managing Docker-based homelab infrastructure across multiple machines.

## Overview

Walheim provides a familiar Kubernetes-like interface for deploying and managing applications in your homelab. Use `whctl` (Walheim Control) to manage namespaces, apps, secrets, and configuration across your physical machines.

**Key Features:**
- kubectl-style CLI interface (`whctl get`, `whctl apply`, etc.)
- Context-based configuration for multiple environments
- Docker Compose as the application definition format
- Kubernetes-style Secret management with automatic injection
- SSH-based deployment to remote machines
- Namespace = physical machine mapping

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
# List all namespaces
whctl get namespaces

# Create a namespace (represents a physical machine)
whctl create namespace production \
  --hostname prod.example.com \
  --username admin
```

### Application Management

```bash
# List apps in a namespace
whctl get apps -n production

# List apps across all namespaces
whctl get apps --all

# Deploy an app
whctl apply app myapp -n production

# Import from docker-compose.yml
whctl import app myapp -n production -f docker-compose.yml

# Start/pause/stop an app
whctl start app myapp -n production
whctl pause app myapp -n production
whctl stop app myapp -n production

# View logs
whctl logs app myapp -n production
whctl logs app myapp -n production --follow
whctl logs app myapp -n production --tail 100
```

### Secret Management

```bash
# List secrets
whctl get secrets -n production

# Deploy a secret
whctl apply secret db-creds -n production

# Secrets are automatically injected into apps via labels
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
    │   │   │   └── docker-compose.yml
    │   │   └── postgres/
    │   │       └── docker-compose.yml
    │   └── secrets/
    │       └── db-creds/
    │           └── secret.yaml
    └── staging/
        ├── .namespace.yaml
        └── apps/
            └── myapp/
                └── docker-compose.yml
```

### Namespace Configuration

Each namespace has a `.namespace.yaml` file with SSH connection details:

```yaml
username: admin
hostname: production.example.com
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
```

Secrets are automatically injected into Docker Compose services:

```yaml
services:
  myapp:
    image: myapp:latest
    labels:
      - walheim.env-from-secrets=db-creds
    environment:
      APP_MODE: production
      # DB_PASSWORD and API_KEY will be injected automatically
```

## Architecture

### Namespaces vs Nodes

Unlike Kubernetes where namespaces are logical and nodes are physical:

- **Walheim namespace = physical machine** (1:1 mapping)
- No scheduling - you explicitly target a namespace with `-n`
- Each namespace has its own SSH credentials

### Deployment Flow

1. You maintain configuration in your data directory (Git repository)
2. Run `whctl apply app myapp -n production`
3. Walheim syncs files to the remote machine via rsync/SSH
4. Runs `docker compose up -d` on the remote machine
5. Secrets are injected before deployment

### Resource Types

- **ClusterResource**: Resources at the top level (e.g., namespaces)
  - Path: `{data_dir}/namespaces/{name}/`
  - Example: `whctl get namespaces`

- **NamespacedResource**: Resources within a namespace (e.g., apps, secrets)
  - Path: `{data_dir}/namespaces/{namespace}/{kind}/{name}/`
  - Example: `whctl get apps -n production`

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
./bin/whctl create namespace demo --hostname localhost

# Verify
./bin/whctl get namespaces
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
