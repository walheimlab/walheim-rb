# frozen_string_literal: true

require_relative "helpers"

module Walheim
  module BaseCommand
    def self.execute(operation:, kind:, name:, options:, parent_options:)
      # 1. Resolve handler
      handler_info = Walheim::HandlerRegistry.get(kind)
      unless handler_info
        warn "Error: unknown kind '#{kind}'"
        warn ""
        warn "Available kinds:"
        Walheim::HandlerRegistry.all_visible.each { |h| warn "  #{h[:name]}" }
        exit 1
      end

      # 2. Check operation support
      handler_class = handler_info[:handler]
      unless Walheim::HandlerRegistry.supports_operation?(kind, operation)
        warn "Error: #{operation} not supported for #{kind}"
        exit 1
      end

      # 3. Get operation metadata
      op_metadata = handler_class.operation_info[operation]
      unless op_metadata
        warn "Error: operation metadata missing for #{operation}"
        exit 1
      end

      # 4. Resolve data directory from context
      data_dir = resolve_data_dir(options, parent_options)

      # 5. Initialize handler
      handler = handler_class.new(data_dir: data_dir)

      # 6. Validate namespace requirements
      validate_namespace_requirements!(operation, kind, name, options, op_metadata) if handler.is_a?(Walheim::NamespacedResource)

      # 7. Dispatch to handler using metadata
      dispatch_operation(handler, operation, name, options, handler_info, op_metadata)
    end

    def self.resolve_data_dir(options, parent_options)
      # Merge options
      all_options = parent_options.merge(options)

      # Try to load config
      begin
        config = Walheim::Config.new(config_path: all_options[:whconfig])

        context_name = all_options[:context] || config.current_context

        if context_name
          config.data_dir(context_name)
        elsif all_options[:data_dir]
          warn "Warning: --data-dir is deprecated. Use contexts."
          all_options[:data_dir]
        else
          warn "Error: No Walheim configuration found."
          warn ""
          warn "Create your first context:"
          warn "  whctl context new <name> --data-dir <path>"
          exit 1
        end
      rescue Walheim::Config::ConfigError, Walheim::Config::ValidationError
        if all_options[:data_dir]
          warn "Warning: --data-dir is deprecated."
          all_options[:data_dir]
        else
          warn "Error: No Walheim configuration found."
          warn ""
          warn "Create your first context:"
          warn "  whctl context new <name> --data-dir <path>"
          exit 1
        end
      end
    end

    def self.validate_namespace_requirements!(operation, kind, _name, options, op_metadata)
      dispatch_meta = op_metadata[:dispatch] || {}
      namespace_handling = dispatch_meta[:namespace_handling]

      case namespace_handling
      when :optional_with_all
        # Operations like get can use --all or -n
        return if options[:all] || options[:namespace]

        warn "Error: either -n {namespace} or --all/-A flag is required"
        warn "Usage: whctl #{operation} #{kind} -n {namespace}"
        warn "Usage: whctl #{operation} #{kind} --all"
        exit 1
      when :required
        # Operations require namespace
        return if options[:namespace]

        warn "Error: -n {namespace} is required"
        warn "Usage: whctl #{operation} #{kind} {name} -n {namespace}"
        exit 1
      when nil
        # No namespace validation needed
        nil
      else
        warn "Error: unknown namespace_handling: #{namespace_handling}"
        exit 1
      end
    end

    def self.dispatch_operation(handler, operation, name, options, handler_info, op_metadata)
      dispatch_meta = op_metadata[:dispatch] || {}
      method_name = dispatch_meta[:method] || operation

      # Build method parameters
      params = build_method_params(name, options, dispatch_meta)

      # Call handler method
      result = handler.send(method_name, **params)

      # Handle output formatting
      handle_output(result, handler, handler_info, options, dispatch_meta)
    end

    def self.build_method_params(name, options, dispatch_meta)
      params = {}

      # Add positional params (like :name)
      positional_params = dispatch_meta[:params] || []
      positional_params.each do |param_name|
        case param_name
        when :name
          params[:name] = name
        else
          params[param_name] = options[param_name]
        end
      end

      # Add named params from options
      named_params = dispatch_meta[:named_params] || {}
      named_params.each do |param_name, option_key|
        option_value = options[option_key]

        # Handle file readers
        if dispatch_meta[:file_reader] == param_name && option_value
          option_value = Walheim::Helpers.read_yaml_input(option_value)
        end

        # Always include declared parameters (handlers expect them as keyword args)
        params[param_name] = option_value
      end

      params
    end

    def self.handle_output(result, handler, handler_info, options, dispatch_meta)
      output_type = dispatch_meta[:output]

      case output_type
      when :table
        # Table output for get operations
        if handler.is_a?(Walheim::ClusterResource)
          Walheim::Helpers.print_cluster_resources_table(result, handler_info[:name])
        else
          Walheim::Helpers.print_resources_table(result, options[:all], handler_info[:name])
        end
      when nil
        # No output handling needed (handler prints directly)
        nil
      else
        warn "Error: unknown output type: #{output_type}"
        exit 1
      end
    end
  end
end
