# frozen_string_literal: true

module Walheim
  class HandlerRegistry
    class << self
      def handlers
        @handlers ||= {}
      end

      def register(kind:, plural:, singular:, handler_class:, aliases: [])
        # Register plural (visible in listings)
        handlers[plural] = {
          handler: handler_class,
          name: plural,
          visible: true,
          info: handler_class.kind_info
        }

        # Register singular (not visible)
        handlers[singular] = {
          handler: handler_class,
          name: plural,
          visible: false,
          info: handler_class.kind_info
        }

        # Register aliases (not visible)
        aliases.each do |alias_name|
          handlers[alias_name] = {
            handler: handler_class,
            name: plural,
            visible: false,
            info: handler_class.kind_info
          }
        end
      end

      def get(kind)
        handlers[kind]
      end

      def all_visible
        handlers.values.select { |h| h[:visible] }.uniq { |h| h[:name] }.sort_by { |h| h[:name] }
      end

      def supports_operation?(kind, operation)
        handler_info = get(kind)
        return false unless handler_info

        handler_class = handler_info[:handler]
        handler_class.public_instance_methods.include?(operation.to_sym)
      end

      # Get all unique operations across all handlers
      def all_operations
        ops = {}
        handlers.values.uniq { |h| h[:handler] }.each do |handler_info|
          handler_class = handler_info[:handler]
          # Get operations from operation_info metadata
          handler_class.operation_info.each_key { |op| ops[op] = true } if handler_class.respond_to?(:operation_info)
        end
        ops.keys.sort
      end

      # Get handlers supporting a specific operation
      def handlers_for_operation(operation)
        all_visible.select do |handler_info|
          supports_operation?(handler_info[:name], operation)
        end
      end

      # Check if handler is cluster or namespaced resource
      def cluster_resource?(kind)
        handler_info = get(kind)
        return false unless handler_info

        handler_info[:handler] < Walheim::ClusterResource
      end
    end
  end
end
