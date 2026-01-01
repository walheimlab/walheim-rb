# frozen_string_literal: true

require_relative '../namespaced_resource'
require_relative '../handler_registry'

module Resources
  class ConfigMaps < Walheim::NamespacedResource
    def self.kind_info
      {
        plural: 'configmaps',
        singular: 'configmap',
        aliases: ['cm']  # Abbreviation
      }
    end

    def self.hooks
      {
        post_create: nil,
        post_update: nil,
        pre_delete: nil
      }
    end

    def self.summary_fields
      {
        keys: lambda { |manifest|
          (manifest['data'] || {}).keys.join(', ')
        }
      }
    end

    private

    def manifest_filename
      'configmap.yaml'
    end
  end
end

# Register handler
info = Resources::ConfigMaps.kind_info
Walheim::HandlerRegistry.register(
  kind: info[:plural],
  plural: info[:plural],
  singular: info[:singular],
  handler_class: Resources::ConfigMaps,
  aliases: info[:aliases] || []
)
