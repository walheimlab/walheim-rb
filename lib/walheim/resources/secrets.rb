# frozen_string_literal: true

require_relative '../namespaced_resource'
require_relative '../handler_registry'

module Resources
  class Secrets < Walheim::NamespacedResource
    def self.kind_info
      {
        plural: 'secrets',
        singular: 'secret'
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
        type: ->(manifest) { manifest['type'] || 'Opaque' },
        keys: lambda { |manifest|
          data_keys = (manifest['data'] || {}).keys
          string_keys = (manifest['stringData'] || {}).keys
          all_keys = (data_keys + string_keys).uniq
          all_keys.join(', ')
        }
      }
    end

    private

    def manifest_filename
      'secret.yaml'
    end
  end
end

# Register handler
info = Resources::Secrets.kind_info
Walheim::HandlerRegistry.register(
  kind: info[:plural],
  plural: info[:plural],
  singular: info[:singular],
  handler_class: Resources::Secrets
)
