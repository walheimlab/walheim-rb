# frozen_string_literal: true

require 'optparse'
require 'terminal-table'

module Walheim
  module LegacyContext
    def self.execute(argv)
      options = {}

      # Remove 'context' from argv since it's already been identified
      argv.shift if argv[0] == 'context'

      # Parse global flags
      global_parser = OptionParser.new do |opts|
        opts.on('--whconfig PATH', 'Alternate config file path') { |v| options[:whconfig] = v }
        opts.on('-d DIR', '--data-dir DIR', 'Data directory') { |v| options[:data_dir] = v }
      end

      # Parse global flags (use parse! to consume all flags)
      begin
        global_parser.parse!(argv)
      rescue OptionParser::InvalidOption => e
        warn "Error: #{e.message}"
        exit 1
      end

      # Get subcommand and context name (now argv only contains non-flag arguments)
      subcommand = argv[0]
      context_name = argv[1]

      case subcommand
      when 'new'
        # whctl context new {name} --data-dir {path}
        unless context_name
          warn 'Error: context name is required'
          warn 'Usage: whctl context new {name} --data-dir {path}'
          exit 1
        end

        unless options[:data_dir]
          warn 'Error: --data-dir flag is required'
          warn 'Usage: whctl context new {name} --data-dir {path}'
          exit 1
        end

        # Validate data_dir exists
        expanded_data_dir = File.expand_path(options[:data_dir])
        unless Dir.exist?(expanded_data_dir)
          warn "Error: data directory '#{expanded_data_dir}' does not exist"
          warn ''
          warn 'Please create the directory first or provide a valid path'
          exit 1
        end

        # Check for namespaces subdirectory
        namespaces_path = File.join(expanded_data_dir, 'namespaces')
        unless Dir.exist?(namespaces_path)
          warn "Warning: data directory does not contain 'namespaces' subdirectory"
          warn "Expected path: #{namespaces_path}"
          warn ''
          warn 'This directory should contain your homelab configuration.'
          warn 'Creating namespaces directory...'
          Dir.mkdir(namespaces_path)
        end

        # Load or create config
        config = Walheim::Config.new(config_path: options[:whconfig])

        begin
          config.add_context(context_name, expanded_data_dir, activate: true)
          config.save_config
          puts "Created context '#{context_name}'"
          puts "  Data directory: #{expanded_data_dir}"
          puts '  Status: Active (automatically activated)'
        rescue Walheim::Config::ValidationError => e
          warn "Error: #{e.message}"
          exit 1
        rescue Walheim::Config::ConfigError => e
          warn "Error: #{e.message}"
          exit 1
        end

      when 'list'
        # whctl context list
        config = Walheim::Config.new(config_path: options[:whconfig])

        unless Walheim::Config.exists?(config_path: options[:whconfig])
          warn 'No Walheim configuration found.'
          warn ''
          warn 'Create your first context:'
          warn '  whctl context new <name> --data-dir <path>'
          exit 1
        end

        contexts = config.list_contexts
        if contexts.empty?
          puts 'No contexts configured.'
          exit 0
        end

        rows = contexts.map do |ctx|
          active_marker = ctx['active'] ? '*' : ''
          [active_marker, ctx['name'], ctx['dataDir']]
        end

        table = Terminal::Table.new do |t|
          t.headings = ['CURRENT', 'NAME', 'DATA DIRECTORY']
          t.rows = rows
          t.style = {
            border_x: '', border_y: '', border_i: '',
            padding_left: 0, padding_right: 3,
            border_top: false, border_bottom: false,
            all_separators: false
          }
        end

        puts table

      when 'use'
        # whctl context use {name}
        unless context_name
          warn 'Error: context name is required'
          warn 'Usage: whctl context use {name}'
          exit 1
        end

        config = Walheim::Config.new(config_path: options[:whconfig])

        begin
          config.use_context(context_name)
          config.save_config
          puts "Switched to context '#{context_name}'"
        rescue Walheim::Config::ConfigError => e
          warn "Error: #{e.message}"
          exit 1
        end

      when 'current'
        # whctl context current
        config = Walheim::Config.new(config_path: options[:whconfig])

        unless Walheim::Config.exists?(config_path: options[:whconfig])
          warn 'No Walheim configuration found.'
          warn ''
          warn 'Create your first context:'
          warn '  whctl context new <name> --data-dir <path>'
          exit 1
        end

        if config.current_context
          puts "Current context: #{config.current_context}"
          puts "Data directory: #{config.data_dir}"
        else
          puts 'No active context selected.'
          puts ''
          puts 'Available contexts:'
          config.list_contexts.each do |ctx|
            puts "  - #{ctx['name']}"
          end
          puts ''
          puts 'Select a context:'
          puts '  whctl context use <context-name>'
        end

      when 'delete'
        # whctl context delete {name}
        unless context_name
          warn 'Error: context name is required'
          warn 'Usage: whctl context delete {name}'
          exit 1
        end

        config = Walheim::Config.new(config_path: options[:whconfig])

        begin
          config.delete_context(context_name)
          config.save_config
          puts "Deleted context '#{context_name}'"

          # Show warning if this was the active context
          unless config.current_context
            puts ''
            puts 'Note: This was your active context.'
            puts 'Select a new context with:'
            puts '  whctl context use <context-name>'
          end
        rescue Walheim::Config::ConfigError => e
          warn "Error: #{e.message}"
          exit 1
        end

      else
        warn "Error: unknown context subcommand '#{subcommand}'"
        warn ''
        warn 'Available context commands:'
        warn '  whctl context new {name} --data-dir {path}'
        warn '  whctl context list'
        warn '  whctl context use {name}'
        warn '  whctl context current'
        warn '  whctl context delete {name}'
        exit 1
      end
    end
  end
end
