# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module Walheim
  # Configuration management for Walheim contexts
  # Handles reading/writing ~/.walheim/config with support for $WHCONFIG override
  class Config
    class ConfigError < StandardError; end
    class ValidationError < ConfigError; end

    DEFAULT_CONFIG_PATH = File.expand_path('~/.walheim/config')
    API_VERSION = 'walheim.io/v1'
    KIND = 'Config'

    attr_reader :current_context, :contexts, :config_path

    # Initialize a new Config instance
    #
    # @param config_path [String, nil] Path to config file (defaults to ~/.walheim/config or $WHCONFIG)
    def initialize(config_path: nil)
      @config_path = resolve_config_path(config_path)
      @current_context = nil
      @contexts = []
      load_config if File.exist?(@config_path)
    end

    # Load configuration from file
    #
    # @return [void]
    # @raise [ConfigError] if file cannot be read or parsed
    # @raise [ValidationError] if config structure is invalid
    def load_config
      data = YAML.load_file(@config_path)
      validate_schema!(data)

      @current_context = data['currentContext']
      @contexts = data['contexts'].map do |ctx|
        {
          'name' => ctx['name'],
          'dataDir' => expand_path(ctx['dataDir'])
        }
      end

      validate_current_context!
    rescue Psych::SyntaxError => e
      raise ConfigError, "Invalid YAML in config file: #{e.message}"
    rescue => e
      raise ConfigError, "Failed to load config: #{e.message}"
    end

    # Save configuration to file (atomic write)
    #
    # @return [void]
    # @raise [ConfigError] if file cannot be written
    def save_config
      data = {
        'apiVersion' => API_VERSION,
        'kind' => KIND,
        'currentContext' => @current_context,
        'contexts' => @contexts.map do |ctx|
          {
            'name' => ctx['name'],
            'dataDir' => ctx['dataDir']
          }
        end
      }

      # Atomic write: write to temp file, then rename
      dir = File.dirname(@config_path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

      temp_file = "#{@config_path}.tmp.#{Process.pid}"
      File.write(temp_file, YAML.dump(data))
      File.rename(temp_file, @config_path)
    rescue => e
      File.delete(temp_file) if temp_file && File.exist?(temp_file)
      raise ConfigError, "Failed to save config: #{e.message}"
    end

    # Get the data directory for a context
    #
    # @param context_name [String, nil] Context name (defaults to current context)
    # @return [String] Path to data directory
    # @raise [ConfigError] if context not found or no current context
    def data_dir(context_name = nil)
      name = context_name || @current_context
      raise ConfigError, 'No active context selected' if name.nil?

      context = find_context(name)
      raise ConfigError, "Context '#{name}' not found" if context.nil?

      context['dataDir']
    end

    # Add a new context
    #
    # @param name [String] Context name
    # @param data_dir [String] Path to data directory
    # @param activate [Boolean] Whether to activate this context immediately
    # @return [void]
    # @raise [ValidationError] if context name already exists
    def add_context(name, data_dir, activate: true)
      raise ValidationError, "Context '#{name}' already exists" if find_context(name)

      @contexts << {
        'name' => name,
        'dataDir' => expand_path(data_dir)
      }

      @current_context = name if activate
    end

    # Remove a context
    #
    # @param name [String] Context name
    # @return [void]
    # @raise [ConfigError] if context not found
    def delete_context(name)
      context = find_context(name)
      raise ConfigError, "Context '#{name}' not found" if context.nil?

      @contexts.delete(context)

      # If we deleted the active context, clear it
      @current_context = nil if @current_context == name
    end

    # Switch to a different context
    #
    # @param name [String] Context name
    # @return [void]
    # @raise [ConfigError] if context not found
    def use_context(name)
      raise ConfigError, "Context '#{name}' not found" unless find_context(name)
      @current_context = name
    end

    # List all contexts
    #
    # @return [Array<Hash>] Array of context hashes with 'name', 'dataDir', and 'active' keys
    def list_contexts
      @contexts.map do |ctx|
        ctx.merge('active' => ctx['name'] == @current_context)
      end
    end

    # Check if config file exists
    #
    # @return [Boolean]
    def self.exists?(config_path: nil)
      path = new(config_path: config_path).config_path
      File.exist?(path)
    end

    private

    # Resolve the config file path with precedence: param > $WHCONFIG > default
    def resolve_config_path(config_path)
      return expand_path(config_path) if config_path
      return expand_path(ENV['WHCONFIG']) if ENV['WHCONFIG']
      DEFAULT_CONFIG_PATH
    end

    # Expand path with ~ support
    def expand_path(path)
      File.expand_path(path)
    end

    # Find a context by name
    def find_context(name)
      @contexts.find { |ctx| ctx['name'] == name }
    end

    # Validate config schema
    def validate_schema!(data)
      raise ValidationError, 'Config must be a Hash' unless data.is_a?(Hash)
      raise ValidationError, "Invalid apiVersion: expected '#{API_VERSION}'" unless data['apiVersion'] == API_VERSION
      raise ValidationError, "Invalid kind: expected '#{KIND}'" unless data['kind'] == KIND
      raise ValidationError, 'Missing required field: contexts' unless data['contexts']
      raise ValidationError, 'contexts must be an Array' unless data['contexts'].is_a?(Array)
      raise ValidationError, 'contexts array cannot be empty' if data['contexts'].empty?

      # Validate each context
      data['contexts'].each_with_index do |ctx, index|
        raise ValidationError, "Context at index #{index} must be a Hash" unless ctx.is_a?(Hash)
        raise ValidationError, "Context at index #{index} missing 'name'" unless ctx['name']
        raise ValidationError, "Context at index #{index} missing 'dataDir'" unless ctx['dataDir']
      end

      # Check for duplicate context names
      names = data['contexts'].map { |ctx| ctx['name'] }
      duplicates = names.select { |name| names.count(name) > 1 }.uniq
      raise ValidationError, "Duplicate context names: #{duplicates.join(', ')}" unless duplicates.empty?
    end

    # Validate that current context (if set) exists in contexts array
    def validate_current_context!
      return if @current_context.nil?
      return if find_context(@current_context)

      raise ValidationError, "Current context '#{@current_context}' not found in contexts"
    end
  end
end
