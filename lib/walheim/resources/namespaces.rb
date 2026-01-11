# frozen_string_literal: true

require "yaml"
require "terminal-table"
require_relative "../cluster_resource"
require_relative "../handler_registry"

module Resources
  class Namespaces < Walheim::ClusterResource
    def self.kind_info
      {
        plural: "namespaces",
        singular: "namespace",
        aliases: [ "ns" ]
      }
    end

    def self.summary_fields
      {
        username: lambda { |manifest|
          # Support both old format (username at root) and new format (username in spec)
          manifest.dig("spec", "username") || manifest["username"] || "N/A"
        },
        hostname: lambda { |manifest|
          # Support both old format (hostname at root) and new format (hostname in spec)
          manifest.dig("spec", "hostname") || manifest["hostname"] || "N/A"
        }
      }
    end

    # Override operation_info for cluster resource
    def self.operation_info
      {
        get: {
          description: "List all namespaces",
          usage: [ "get namespaces" ],
          options: {}, # No namespace flag for cluster resource
          dispatch: {
            method: :get,
            params: [ :name ],
            output: :table
          }
        },
        create: {
          description: "Create a new namespace",
          usage: [ "create namespace {name} [--username {user}] [--hostname {host}]" ],
          options: {
            username: { type: :string, desc: "SSH username for namespace" },
            hostname: { type: :string, desc: "Hostname for namespace" }
          },
          dispatch: {
            method: :create,
            params: [ :name ],
            named_params: {
              username: :username,
              hostname: :hostname
            }
          }
        },
        apply: {
          description: "Create or update namespace",
          usage: [ "apply namespace {name}", "apply -f namespace.yaml" ],
          options: {
            file: { type: :string, aliases: [ :f ], desc: "Manifest file" }
          },
          dispatch: {
            method: :apply,
            params: [ :name ],
            named_params: {
              manifest_source: :file
            }
          }
        },
        delete: {
          description: "Delete a namespace",
          usage: [ "delete namespace {name}" ],
          options: {},
          dispatch: {
            method: :delete,
            params: [ :name ]
          }
        },
        describe: {
          description: "Show detailed namespace information",
          usage: [ "describe namespace {name}" ],
          options: {},
          dispatch: {
            method: :describe,
            params: [ :name ]
          }
        }
      }
    end

    # Create a new namespace
    def create(name:, username: nil, hostname: nil)
      hostname ||= name

      namespace_path = File.join(@data_dir, "namespaces", name)
      if Dir.exist?(namespace_path)
        warn "Error: namespace '#{name}' already exists at #{namespace_path}"
        exit 1
      end

      # Create directory structure
      Dir.mkdir(namespace_path)
      Dir.mkdir(File.join(namespace_path, "apps"))
      Dir.mkdir(File.join(namespace_path, "secrets"))
      Dir.mkdir(File.join(namespace_path, "configmaps"))

      # Create .namespace.yaml in k8s-style format
      namespace_manifest = {
        "apiVersion" => "walheim/v1alpha1",
        "kind" => "Namespace",
        "metadata" => {
          "name" => name
        },
        "spec" => {
          "hostname" => hostname
        }
      }

      # Add username to spec if provided
      namespace_manifest["spec"]["username"] = username if username

      File.write(File.join(namespace_path, ".namespace.yaml"), YAML.dump(namespace_manifest))

      puts "Created namespace '#{name}' at #{namespace_path}"
      puts "  Username: #{username || '(from SSH config)'}"
      puts "  Hostname: #{hostname}"
    end

    # Describe a namespace with detailed information
    def describe(name:)
      namespace_path = File.join(@data_dir, "namespaces", name)
      unless Dir.exist?(namespace_path)
        warn "Error: namespace '#{name}' not found"
        exit 1
      end

      # Load namespace config
      config_path = File.join(namespace_path, ".namespace.yaml")
      unless File.exist?(config_path)
        warn "Error: namespace config not found at #{config_path}"
        exit 1
      end

      config = YAML.load_file(config_path)

      # Support both old format (username/hostname at root) and new format (in spec)
      username = config.dig("spec", "username") || config["username"]
      hostname = config.dig("spec", "hostname") || config["hostname"]
      remote_host = username ? "#{username}@#{hostname}" : hostname

      # Print metadata
      puts "Name:           #{name}"
      puts "Hostname:       #{hostname}"
      puts "Username:       #{username || '(from SSH config)'}"
      puts "SSH:            #{remote_host}"
      puts ""

      # Test SSH connectivity and Docker availability
      puts "Status:"
      connection_status = test_ssh_connection(remote_host)
      puts "  Connection:   #{connection_status[:status]}"

      if connection_status[:connected]
        docker_info = get_docker_info(remote_host)
        puts "  Docker:       #{docker_info[:status]}"
        puts ""

        # Get deployed apps with status
        apps_info = get_deployed_apps(name, remote_host)
        if apps_info[:apps].any?
          puts "Deployed Apps:"
          apps_info[:apps].each do |app|
            status_display = format_app_status(app[:status])
            ready_display = app[:ready] || "-"
            puts "  %-15s %-12s %s" % [ app[:name], status_display, ready_display ]
          end
          puts ""
        end

        # Count resources
        puts "Resources:"
        apps_count = count_resources(namespace_path, "apps")
        secrets_count = count_resources(namespace_path, "secrets")
        configmaps_count = count_resources(namespace_path, "configmaps")
        puts "  Apps:         #{apps_count}"
        puts "  Secrets:      #{secrets_count}"
        puts "  ConfigMaps:   #{configmaps_count}"
        puts ""

        # Show usage info if available
        if docker_info[:connected]
          usage_info = get_usage_info(remote_host)
          if usage_info[:available]
            puts "Usage:"
            puts "  Disk:         #{usage_info[:disk]}" if usage_info[:disk]
            puts "  Containers:   #{usage_info[:containers]}" if usage_info[:containers]
          end
        end
      else
        puts ""
        puts "Unable to connect to namespace. Please check SSH configuration."
      end
    end

    private

    # Test SSH connection to remote host
    def test_ssh_connection(remote_host)
      # Try a simple SSH command with timeout
      test_command = "ssh -o ConnectTimeout=5 -o BatchMode=yes #{remote_host} 'echo ok' 2>/dev/null"
      result = `#{test_command}`.strip

      if result == "ok"
        { connected: true, status: "Connected" }
      else
        { connected: false, status: "Failed" }
      end
    end

    # Get Docker version and availability
    def get_docker_info(remote_host)
      docker_command = "ssh -o ConnectTimeout=5 #{remote_host} 'docker --version' 2>/dev/null"
      result = `#{docker_command}`.strip

      if result.include?("Docker version")
        version = result.match(/Docker version ([\d.]+)/)[1] rescue "unknown"
        { connected: true, status: "Available (v#{version})" }
      else
        { connected: false, status: "Not available" }
      end
    end

    # Get list of deployed apps with their status
    def get_deployed_apps(namespace, remote_host)
      require "shellwords"

      # Query all containers for this namespace
      docker_cmd = "docker ps -a --filter label=walheim.namespace=" + namespace + ' --format "{{.Label \\"walheim.app\\"}}|{{.State}}|{{.Status}}"'
      ssh_command = "ssh #{remote_host} #{Shellwords.escape(docker_cmd)} 2>/dev/null"
      output = `#{ssh_command}`

      # Parse container data
      apps_data = {}
      output.each_line do |line|
        parts = line.strip.split("|")
        next if parts.size < 3

        app_name = parts[0]
        state = parts[1]
        status_text = parts[2]

        apps_data[app_name] ||= { containers: [] }
        apps_data[app_name][:containers] << { state: state, status: status_text }
      end

      # Convert to app list with aggregated status
      apps = apps_data.map do |app_name, data|
        containers = data[:containers]
        total = containers.size
        running = containers.count { |c| c[:state] == "running" }
        ready = "#{running}/#{total}"

        # Determine overall status
        states = containers.map { |c| c[:state] }.uniq
        status = if states.all? { |s| s == "running" }
                   "Running"
        elsif states.all? { |s| s == "exited" }
                   "Stopped"
        elsif states.include?("running")
                   "Degraded"
        elsif states.include?("paused")
                   "Paused"
        else
                   "Unknown"
        end

        { name: app_name, status: status, ready: ready }
      end

      { apps: apps.sort_by { |a| a[:name] } }
    end

    # Format app status for display
    def format_app_status(status)
      case status
      when "Running"
        status
      when "Degraded"
        status
      when "Stopped"
        status
      when "Paused"
        status
      else
        status
      end
    end

    # Count resources in a namespace directory
    def count_resources(namespace_path, resource_type)
      resource_dir = File.join(namespace_path, resource_type)
      return 0 unless Dir.exist?(resource_dir)

      Dir.entries(resource_dir)
         .select { |entry| File.directory?(File.join(resource_dir, entry)) && !entry.start_with?(".") }
         .size
    end

    # Get usage information from remote host
    def get_usage_info(remote_host)
      # Get disk usage
      disk_command = "ssh #{remote_host} 'df -h /data 2>/dev/null | tail -1' 2>/dev/null"
      disk_output = `#{disk_command}`.strip
      disk_info = nil
      if disk_output && !disk_output.empty?
        parts = disk_output.split
        disk_info = "#{parts[2]} / #{parts[1]}" if parts.size >= 4
      end

      # Get container counts
      container_command = "ssh #{remote_host} 'docker ps -q | wc -l; docker ps -aq | wc -l' 2>/dev/null"
      container_output = `#{container_command}`.strip
      container_info = nil
      if container_output && !container_output.empty?
        lines = container_output.split("\n")
        if lines.size == 2
          running = lines[0].strip.to_i
          total = lines[1].strip.to_i
          stopped = total - running
          container_info = "#{running} running"
          container_info += ", #{stopped} stopped" if stopped > 0
        end
      end

      {
        available: disk_info || container_info,
        disk: disk_info,
        containers: container_info
      }
    end


    def manifest_filename
      ".namespace.yaml"
    end
  end
end

# Register handler
info = Resources::Namespaces.kind_info
Walheim::HandlerRegistry.register(
  kind: info[:plural],
  plural: info[:plural],
  singular: info[:singular],
  handler_class: Resources::Namespaces,
  aliases: info[:aliases] || []
)
