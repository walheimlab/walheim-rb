# Context Usage Scenarios

This document provides practical examples of using Walheim contexts for different use cases.

## Scenario 1: Single Homelab Setup

**Use Case:** You have one homelab and want to get started quickly.

```bash
# Initial setup
whctl context new homelab --data-dir ~/homelab

# Create your first namespace
whctl create namespace prod-server --hostname 192.168.1.100 --username admin

# All commands use the homelab context automatically
whctl get namespaces
whctl apply app nginx -n prod-server
```

## Scenario 2: Multi-Environment Setup

**Use Case:** Separate dev/staging/production environments.

```bash
# Set up contexts
whctl context new development --data-dir ~/homelab-dev
whctl context new staging --data-dir ~/homelab-staging
whctl context new production --data-dir ~/homelab-prod

# List contexts
whctl context list

# Switch between environments
whctl context use development
whctl apply app myapp -n dev-node1

# Quick check on staging
whctl --context staging get apps --all
```

## Scenario 3: Multiple Physical Locations

**Use Case:** Homelabs in different locations (home, office, remote).

```bash
# Create contexts for each location
whctl context new home --data-dir ~/homelabs/home
whctl context new office --data-dir ~/homelabs/office
whctl context new remote-site --data-dir ~/homelabs/remote

# Deploy to each location
whctl --context home apply app monitoring -n home-server1
whctl --context office apply app monitoring -n office-server
```

## Scenario 4: Testing with Isolated Config

**Use Case:** Test without affecting your main configuration.

```bash
# Use separate config file
export WHCONFIG=/tmp/test-config.yaml
whctl context new test --data-dir /tmp/test-homelab

# Test operations
whctl create namespace test-ns --hostname localhost

# Clean up
rm -rf /tmp/test-homelab /tmp/test-config.yaml
unset WHCONFIG
```

## Best Practices

### Naming Conventions
- Use descriptive names: `production`, `staging`, `development`
- Include location/purpose: `home-lab`, `office-lab`, `client-acme`
- Avoid generic names: `ctx1`, `test`, `temp`

### Data Directory Organization
```
~/homelabs/
├── production/
│   ├── .git/
│   └── namespaces/
├── staging/
│   ├── .git/
│   └── namespaces/
└── development/
    ├── .git/
    └── namespaces/
```

### Backup Your Config
```bash
# Backup
cp ~/.walheim/config ~/.walheim/config.backup

# Or use dotfiles
ln -s ~/dotfiles/walheim/config ~/.walheim/config
```

### Use Context Override for Safety
```bash
# Explicit context for critical operations
whctl --context production delete namespace critical-server
```

## Troubleshooting

### "No Walheim configuration found"
```bash
# Create your first context
whctl context new homelab --data-dir ~/my-homelab
```

### "Context 'xyz' not found"
```bash
# List available contexts
whctl context list

# Use valid context
whctl context use production
```

### Working with Multiple Config Files
```bash
# Use WHCONFIG environment variable
WHCONFIG=~/.walheim/config.work whctl context list

# Or --whconfig flag
whctl --whconfig ~/.walheim/config.work get namespaces
```
