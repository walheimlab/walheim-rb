# Walheim Config File Schema

## Overview

The Walheim configuration file provides kubectl-style context management for multiple homelab environments.

**Default Location:** `~/.walheim/config`

**Override Options:**
- `--whconfig <path>` flag
- `$WHCONFIG` environment variable

## YAML Schema

```yaml
apiVersion: walheim.io/v1
kind: Config
currentContext: <string>
contexts:
  - name: <string>
    dataDir: <string>
  - name: <string>
    dataDir: <string>
```

## Field Descriptions

### `apiVersion` (required)
- Type: `string`
- Value: `walheim.io/v1`
- Description: Schema version for future compatibility

### `kind` (required)
- Type: `string`
- Value: `Config`
- Description: Resource type identifier

### `currentContext` (optional)
- Type: `string`
- Description: Name of the currently active context. Must match one of the context names in the `contexts` array.
- Validation: If set, must reference an existing context name
- Default: If not set or file doesn't exist, whctl shows instructions to run `whctl context new`

### `contexts` (required)
- Type: `array of objects`
- Description: List of available contexts
- Each context object contains:
  - `name` (required): Unique identifier for the context
  - `dataDir` (required): Absolute or relative path to the data directory containing `namespaces/` subdirectory

## Example Configuration

```yaml
apiVersion: walheim.io/v1
kind: Config
currentContext: production
contexts:
  - name: production
    dataDir: /home/user/homelab-prod
  - name: staging
    dataDir: /home/user/homelab-staging
  - name: local
    dataDir: ~/walheim-local
```

## Validation Rules

1. **Unique Context Names**: Each context name must be unique within the `contexts` array
2. **Valid Current Context**: If `currentContext` is set, it must match one of the context names
3. **Data Directory**: Each `dataDir` should be a valid path (validated at runtime)
4. **Required Fields**: `apiVersion`, `kind`, and `contexts` are required
5. **Array Not Empty**: The `contexts` array must contain at least one context

## Behavior Scenarios

### Missing Config File
When `~/.walheim/config` doesn't exist:
```
Error: No Walheim configuration found.

Run the following command to create your first context:
  whctl context new <name> --data-dir <path>

Example:
  whctl context new homelab --data-dir ~/my-homelab
```

### No Current Context Set
When config exists but `currentContext` is empty or missing:
```
Error: No active context selected.

Available contexts:
  - production
  - staging

Select a context:
  whctl context use <context-name>

Or create a new one:
  whctl context new <name> --data-dir <path>
```

### Invalid Current Context
When `currentContext` references a non-existent context:
```
Error: Current context 'missing-context' not found in configuration.

Available contexts:
  - production
  - staging

Select a valid context:
  whctl context use <context-name>
```

## Implementation Notes

### File Operations
- **Create**: `whctl context new` creates the file if it doesn't exist
- **Read**: All commands read this file to determine the data directory
- **Update**: Context commands modify this file (use, delete, new)
- **Format**: Preserve YAML formatting and comments when updating

### Path Resolution
- Expand `~` to user home directory
- Support both absolute and relative paths
- Relative paths are resolved from config file location or current working directory

### Atomic Updates
When updating the config file:
1. Read current config
2. Modify in memory
3. Write to temporary file
4. Atomic rename to `~/.walheim/config`

This prevents corruption if the process is interrupted during write.
