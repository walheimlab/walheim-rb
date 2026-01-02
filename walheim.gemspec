# frozen_string_literal: true

require_relative 'lib/walheim/version'

Gem::Specification.new do |spec|
  spec.name = 'walheim'
  spec.version = Walheim::VERSION
  spec.authors = ['Akhyar Amarullah']
  spec.email = ['akhyar@chickenzord.com']

  spec.summary = 'Docker-based homelab configuration management with kubectl-like CLI'
  spec.description = 'Walheim is a Docker-based homelab configuration management system with a kubectl-like CLI called whctl. Manage your homelab infrastructure with familiar Kubernetes-style commands.'
  spec.homepage = 'https://github.com/walheimlab/walheim-rb'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/walheimlab/walheim-rb'
  spec.metadata['changelog_uri'] = 'https://github.com/walheimlab/walheim-rb/blob/main/CHANGELOG.md'

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob('{bin,lib}/**/*') + %w[README.md]
  spec.bindir = 'bin'
  spec.executables = ['whctl']
  spec.require_paths = ['lib']

  # Dependencies
  spec.add_dependency 'terminal-table', '~> 3.0'
  spec.add_dependency 'thor', '~> 1.3'

  # Development dependencies
  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 13.0'
end
