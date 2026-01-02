# frozen_string_literal: true

require 'yaml'
require 'terminal-table'
require_relative '../cluster_resource'
require_relative '../handler_registry'

module Resources
  class Namespaces < Walheim::ClusterResource
    def self.kind_info
      {
        plural: 'namespaces',
        singular: 'namespace',
        aliases: ['ns']
      }
    end

    def self.summary_fields
      {
        username: ->(manifest) { manifest['username'] || 'N/A' },
        hostname: ->(manifest) { manifest['hostname'] || 'N/A' }
      }
    end

    # Override operation_info for cluster resource
    def self.operation_info
      {
        get: {
          description: 'List all namespaces',
          usage: ['get namespaces'],
          options: {} # No namespace flag for cluster resource
        },
        create: {
          description: 'Create a new namespace',
          usage: ['create namespace {name} [--username {user}] [--hostname {host}]'],
          options: {
            username: { type: :string, desc: 'SSH username for namespace' },
            hostname: { type: :string, desc: 'Hostname for namespace' }
          }
        },
        apply: {
          description: 'Create or update namespace',
          usage: ['apply namespace {name}', 'apply -f namespace.yaml'],
          options: {
            file: { type: :string, aliases: [:f], desc: 'Manifest file' }
          }
        },
        delete: {
          description: 'Delete a namespace',
          usage: ['delete namespace {name}'],
          options: {}
        }
      }
    end

    # Create a new namespace
    def create(name:, username: nil, hostname: nil)
      hostname ||= name

      namespace_path = File.join(@data_dir, 'namespaces', name)
      if Dir.exist?(namespace_path)
        warn "Error: namespace '#{name}' already exists at #{namespace_path}"
        exit 1
      end

      # Create directory structure
      Dir.mkdir(namespace_path)
      Dir.mkdir(File.join(namespace_path, 'apps'))
      Dir.mkdir(File.join(namespace_path, 'secrets'))
      Dir.mkdir(File.join(namespace_path, 'configmaps'))

      # Create .namespace.yaml with optional username
      config_content = "hostname: #{hostname}\n"
      config_content = "username: #{username}\n#{config_content}" if username
      File.write(File.join(namespace_path, '.namespace.yaml'), config_content)

      puts "Created namespace '#{name}' at #{namespace_path}"
      puts "  Username: #{username || '(from SSH config)'}"
      puts "  Hostname: #{hostname}"
    end

    private

    def manifest_filename
      '.namespace.yaml'
    end
  end
end

# Register handler
info = Resources::Namespaces.kind_info
Walheim::HandlerRegistry.register(
  kind: info[:plural],
  plural: info[:plural],
  singular: info[:singular],
  handler_class: Resources::Namespaces,
  aliases: info[:aliases] || []
)
