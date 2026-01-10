# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `whctl pull` command for apps to pull latest images without restarting containers

## [0.1.0] - TBD

### Added
- Initial release of Walheim
- kubectl-style context management for homelab configuration
- `whctl` CLI tool for managing Docker-based homelab infrastructure
- Context commands: `new`, `list`, `use`, `current`, `delete`
- Resource management: namespaces, apps, secrets, configmaps
- Commands: `get`, `apply`, `create`, `delete`, `start`, `pause`, `stop`, `logs`
- Kubernetes-style Secret management with automatic injection
- SSH-based deployment using rsync and docker compose
- Configuration file support (`~/.walheim/config`)
- Global flags: `--context`, `--whconfig`

### Documentation
- Comprehensive README with installation and usage guide
- Context usage scenarios guide
- Config schema documentation

[Unreleased]: https://github.com/walheimlab/walheim-rb/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/walheimlab/walheim-rb/releases/tag/v0.1.0
