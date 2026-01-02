# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'terminal-table'

module Walheim
  # Base Resource class containing common functionality for all resource types
  # Subclasses:
  # - NamespacedResource: for namespace-scoped resources (apps, secrets, configmaps)
  # - ClusterResource: for cluster-scoped resources (namespaces)
  class Resource
    attr_reader :data_dir

    def initialize(data_dir: Dir.pwd)
      @data_dir = data_dir
    end

    # Metadata - must be overridden by subclasses
    def self.kind_info
      raise NotImplementedError, 'Subclass must implement kind_info'
    end

    # Lifecycle hooks - can be overridden by subclasses
    def self.hooks
      {
        post_create: nil,    # Method name to call after create
        post_update: nil,    # Method name to call after update
        pre_delete: nil      # Method name to call before delete
      }
    end

    # Summary fields for get output - can be overridden by subclasses
    def self.summary_fields
      {}  # Default: no summary fields
    end

    # Operation metadata - defines how operations appear in help
    # Subclasses can override to add custom operations
    def self.operation_info
      {
        get: {
          description: 'List or retrieve resources',
          usage: [
            "get #{kind_info[:plural]} -n {namespace}",
            "get #{kind_info[:plural]} --all/-A",
            "get #{kind_info[:singular]} {name} -n {namespace}"
          ],
          options: {}  # Subclasses will override
        },
        apply: {
          description: 'Create or update a resource',
          usage: ["apply #{kind_info[:singular]} {name} -n {namespace}"],
          options: {
            file: { type: :string, aliases: [:f], desc: 'Manifest file (use - for stdin)' }
          }
        },
        delete: {
          description: 'Delete a resource',
          usage: ["delete #{kind_info[:singular]} {name} -n {namespace}"],
          options: {}  # Subclasses will override
        }
      }
    end

    protected

    # Trigger lifecycle hooks
    def trigger_hook(hook_type, **kwargs)
      hook_method = self.class.hooks[hook_type]
      return unless hook_method

      send(hook_method, **kwargs)
    end

    # Default manifest filename - subclasses can override
    def manifest_filename
      "#{self.class.kind_info[:singular]}.yaml"
    end
  end
end
