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
    end
  end
end
