# frozen_string_literal: true

require "thor"
require_relative "cli/helpers"
require_relative "cli/base_command"
require_relative "cli/resource_command"

module Walheim
  class CLI < Thor
    # Exit with non-zero status on errors
    def self.exit_on_failure?
      true
    end

    # Global flags
    class_option :context,
                 type: :string,
                 desc: "Override active context"

    class_option :whconfig,
                 type: :string,
                 desc: "Alternate config file path"

    class_option :data_dir,
                 type: :string,
                 aliases: [ :d ],
                 desc: "Data directory (deprecated: use contexts)"

    # Dynamically register operations
    def self.register_operations
      Walheim::HandlerRegistry.all_operations.each do |operation|
        ResourceCommand.register_operation(self, operation)
      end
    end

    # Version command
    desc "version", "Show version"
    def version
      puts "whctl version #{Walheim::VERSION}"
    end

    # Exec command - custom implementation to support variadic arguments
    desc "exec app NAME [--] COMMAND...", "Execute command in app container"
    method_option :namespace,
                  type: :string,
                  aliases: [ :n ],
                  desc: "Target namespace",
                  required: true
    method_option :service,
                  type: :string,
                  aliases: [ :s ],
                  desc: "Target service (defaults to first)"
    method_option :interactive,
                  type: :boolean,
                  aliases: [ :it ],
                  desc: "Allocate pseudo-TTY and keep stdin open",
                  default: false
    def exec(kind, name, *command)
      # Validate kind is 'app' or 'apps'
      unless %w[app apps].include?(kind.downcase)
        warn "Error: exec only supports 'app' kind, got '#{kind}'"
        exit 1
      end

      # Resolve data directory from context
      data_dir = BaseCommand.send(:resolve_data_dir, options, self.class.class_options.transform_keys(&:to_sym).transform_values { |v| options[v.name] rescue nil })

      # Initialize Apps handler
      handler = Resources::Apps.new(data_dir: data_dir)

      # Call exec_command method
      handler.exec_command(
        namespace: options[:namespace],
        name: name,
        service: options[:service],
        interactive: options[:interactive],
        command: command
      )
    end

    # Override help to maintain kubectl-style help
    def self.help(shell, subcommand = false)
      list = printable_commands(true, subcommand)
      Thor::Util.thor_classes_in(self).each do |klass|
        list += klass.printable_commands(false)
      end

      # Group commands by category
      shell.say "Usage: whctl [global flags] <command> [arguments]"
      shell.say ""
      shell.say "Global flags:"
      shell.say "  --context CONTEXT     Override active context for this command"
      shell.say "  --whconfig PATH       Use alternate config file (default: ~/.walheim/config)"
      shell.say "  -d, --data-dir DIR    Data directory containing namespaces (deprecated: use contexts)"
      shell.say ""
      shell.say "Available commands:"
      shell.say ""

      # Print commands
      list.each do |command|
        next if command[0] == "help"

        shell.say "  #{command[0].ljust(30)} #{command[1]}"
      end
    end
  end
end
