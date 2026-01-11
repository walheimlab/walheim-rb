# frozen_string_literal: true

require "yaml"

module Walheim
  class Sync
    def initialize(namespaces_dir: "namespaces", remote_base_dir: "/data/walheim")
      @namespaces_dir = namespaces_dir
      @remote_base_dir = remote_base_dir
    end

    def sync(namespace:, kind:, name:)
      namespace_config = load_namespace_config(namespace)
      # Support both old format (username/hostname at root) and new format (in spec)
      username = namespace_config.dig("spec", "username") || namespace_config["username"]
      hostname = namespace_config.dig("spec", "hostname") || namespace_config["hostname"]

      # Build remote host string (with optional username)
      remote_host = username ? "#{username}@#{hostname}" : hostname

      local_dir = "#{@namespaces_dir}/#{namespace}/#{kind}/#{name}/"
      remote_dir = "#{@remote_base_dir}/#{kind}/#{name}/"

      # Validate local directory exists
      unless Dir.exist?(local_dir)
        warn "Error: local directory '#{local_dir}' not found"
        exit 1
      end

      # Ensure remote directory exists
      puts "Creating remote directory: #{remote_dir}"
      system("ssh #{remote_host} 'mkdir -p #{remote_dir}'")

      # Sync files
      puts "Syncing #{local_dir} to #{remote_host}:#{remote_dir}"
      sync_result = system("rsync -avz --delete #{local_dir} #{remote_host}:#{remote_dir}")

      unless sync_result
        warn "Error: rsync failed"
        exit 1
      end

      puts "Synchronized #{local_dir} to #{remote_host}:#{remote_dir}"

      { username: username, hostname: hostname, remote_dir: remote_dir }
    end

    private

    def load_namespace_config(namespace)
      config_path = "#{@namespaces_dir}/#{namespace}/.namespace.yaml"

      unless File.exist?(config_path)
        warn "Error: namespace config '#{config_path}' not found"
        exit 1
      end

      YAML.load_file(config_path)
    end
  end
end
