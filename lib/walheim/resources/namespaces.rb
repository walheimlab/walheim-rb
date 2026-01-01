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
