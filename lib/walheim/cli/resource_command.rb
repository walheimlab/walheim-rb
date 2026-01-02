# frozen_string_literal: true

require_relative 'base_command'

module Walheim
  module ResourceCommand
    def self.register_operation(cli_class, operation)
      # Get handlers supporting this operation
      handlers = Walheim::HandlerRegistry.handlers_for_operation(operation)
      return if handlers.empty?

      # Build command description
      descriptions = handlers.map { |h| h[:name] }.join(', ')
      desc_text = "#{operation.to_s.capitalize} resources (#{descriptions})"

      # Define Thor command
      cli_class.desc "#{operation} KIND [NAME]", desc_text

      # Add operation-specific options from handler metadata
      # Collect all unique options across handlers for this operation
      all_options = {}
      handlers.each do |handler_info|
        handler_class = handler_info[:handler]
        if handler_class.respond_to?(:operation_info)
          op_metadata = handler_class.operation_info[operation]
          if op_metadata && op_metadata[:options]
            all_options.merge!(op_metadata[:options])
          end
        end
      end

      # Register options with Thor
      all_options.each do |opt_name, opt_config|
        # Thor expects method_option calls
        # We'll need to call this dynamically
        cli_class.method_option opt_name, opt_config
      end

      # Define command method
      cli_class.define_method(operation) do |kind, name = nil|
        BaseCommand.execute(
          operation: operation,
          kind: kind,
          name: name,
          options: options,
          parent_options: self.class.class_options.transform_keys(&:to_sym).transform_values { |v| options[v.name] rescue nil }
        )
      end
    end
  end
end
