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
      unless Walheim::HandlerRegistry.supports_operation?(kind, operation)
        warn "Error: #{operation} not supported for #{kind}"
        exit 1
      end

      # 3. Resolve data directory from context
      data_dir = resolve_data_dir(options, parent_options)

      # 4. Initialize handler
      handler = handler_info[:handler].new(data_dir: data_dir)

      # 5. Validate namespace requirements
      validate_namespace_options!(operation, kind, name, options) if handler.is_a?(Walheim::NamespacedResource)

      # 6. Dispatch to handler
      dispatch_to_handler(handler, operation, name, options, handler_info)
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

    def self.validate_namespace_options!(operation, kind, _name, options)
      # Operations that require namespace or --all
      requires_namespace = %i[get apply delete start pause stop logs pull import]
      return unless requires_namespace.include?(operation)

      # get can use --all
      if operation == :get
        return if options[:all] || options[:namespace]

        warn "Error: either -n {namespace} or --all/-A flag is required"
        warn "Usage: whctl get #{kind} -n {namespace}"
        warn "Usage: whctl get #{kind} --all"
        exit 1
      end

      # Other operations require namespace
      return if options[:namespace]

      warn "Error: -n {namespace} is required"
      warn "Usage: whctl #{operation} #{kind} {name} -n {namespace}"
      exit 1
    end

    def self.dispatch_to_handler(handler, operation, name, options, handler_info)
      case operation
      when :get
        dispatch_get(handler, name, options, handler_info)
      when :apply
        dispatch_apply(handler, name, options, handler_info)
      when :delete
        handler.delete(namespace: options[:namespace], name: name)
      when :create
        # Special case: create namespace
        handler.create(name: name, username: options[:username], hostname: options[:hostname])
      when :import
        # Special case: import app
        compose_manifest = Walheim::Helpers.read_yaml_input(options[:file])
        handler.import(namespace: options[:namespace], name: name, compose_manifest: compose_manifest)
      when :start, :pause, :stop, :pull
        handler.send(operation, namespace: options[:namespace], name: name)
      when :logs
        log_opts = {}
        log_opts[:follow] = options[:follow] if options[:follow]
        log_opts[:tail] = options[:tail] if options[:tail]
        log_opts[:timestamps] = options[:timestamps] if options[:timestamps]
        handler.logs(namespace: options[:namespace], name: name, **log_opts)
      else
        warn "Error: operation #{operation} not implemented"
        exit 1
      end
    end

    def self.dispatch_get(handler, name, options, handler_info)
      if handler.is_a?(Walheim::ClusterResource)
        result = handler.get(name: name)
        Walheim::Helpers.print_cluster_resources_table(result, handler_info[:name])
      else
        result = if options[:all]
                   handler.get(namespace: nil, name: nil)
        else
                   handler.get(namespace: options[:namespace], name: name)
        end
        Walheim::Helpers.print_resources_table(result, options[:all], handler_info[:name])
      end
    end

    def self.dispatch_apply(handler, name, options, _handler_info)
      # Extract from manifest if -f provided
      if options[:file]
        manifest_data = Walheim::Helpers.read_yaml_input(options[:file])

        if handler.is_a?(Walheim::NamespacedResource)
          namespace = manifest_data["metadata"]["namespace"]
          name = manifest_data["metadata"]["name"]

          unless namespace && name
            warn "Error: Manifest must contain metadata.namespace and metadata.name"
            exit 1
          end

          handler.apply(namespace: namespace, name: name, manifest_source: options[:file])
        else
          # Cluster resource
          name = manifest_data["metadata"]["name"]
          unless name
            warn "Error: Manifest must contain metadata.name"
            exit 1
          end
          handler.apply(name: name, manifest_source: options[:file])
        end
      elsif handler.is_a?(Walheim::NamespacedResource)
        # Apply from existing manifest in data dir
        handler.apply(namespace: options[:namespace], name: name)
      else
        handler.apply(name: name)
      end
    end
  end
end
