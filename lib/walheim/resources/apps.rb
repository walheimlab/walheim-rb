# frozen_string_literal: true

require_relative "../namespaced_resource"
require_relative "../sync"
require_relative "../handler_registry"

module Resources
  class Apps < Walheim::NamespacedResource
    def initialize(data_dir: Dir.pwd)
      super(data_dir: data_dir)
      # Sync needs the full path to namespaces directory
      @namespaces_dir = File.join(data_dir, "namespaces")
      @syncer = Walheim::Sync.new(namespaces_dir: @namespaces_dir)
    end

    def self.kind_info
      {
        plural: "apps",
        singular: "app",
        aliases: %w[application applications]
      }
    end

    def self.hooks
      {
        post_create: :start,
        post_update: :start,
        pre_delete: :stop
      }
    end

    def self.summary_fields
      {
        image: lambda { |manifest|
          # Extract first service's image from compose spec
          manifest.dig("spec", "compose", "services")&.values&.first&.dig("image") || "N/A"
        },
        status: lambda { |_manifest|
          # Could check if app is running, for now just show 'Configured'
          "Configured"
        }
      }
    end

    def self.operation_info
      # Start with base operations
      ops = super

      namespace_opt = { type: :string, aliases: [ :n ], desc: "Target namespace", required: true }

      # Add apps-specific operations
      ops.merge({
                  import: {
                    description: "Import docker-compose as Walheim App",
                    usage: [ "import app {name} -n {namespace} -f {docker-compose.yml}" ],
                    options: {
                      namespace: namespace_opt,
                      file: { type: :string, aliases: [ :f ], desc: "docker-compose.yml path", required: true }
                    },
                    dispatch: {
                      method: :import,
                      params: [:name],
                      named_params: {
                        namespace: :namespace,
                        compose_manifest: :file
                      },
                      namespace_handling: :required,
                      file_reader: :compose_manifest # Read YAML from file option
                    }
                  },
                  start: {
                    description: "Compile, sync, and start app on host",
                    usage: [ "start app {name} -n {namespace}" ],
                    options: { namespace: namespace_opt },
                    dispatch: {
                      method: :start,
                      params: [:name],
                      named_params: { namespace: :namespace },
                      namespace_handling: :required
                    }
                  },
                  pause: {
                    description: "Stop app containers (keep files)",
                    usage: [ "pause app {name} -n {namespace}" ],
                    options: { namespace: namespace_opt },
                    dispatch: {
                      method: :pause,
                      params: [:name],
                      named_params: { namespace: :namespace },
                      namespace_handling: :required
                    }
                  },
                  stop: {
                    description: "Stop app and remove files from host",
                    usage: [ "stop app {name} -n {namespace}" ],
                    options: { namespace: namespace_opt },
                    dispatch: {
                      method: :stop,
                      params: [:name],
                      named_params: { namespace: :namespace },
                      namespace_handling: :required
                    }
                  },
                  logs: {
                    description: "View logs from remote containers",
                    usage: [
                      "logs app {name} -n {namespace}",
                      "logs app {name} -n {namespace} --follow",
                      "logs app {name} -n {namespace} --tail 100",
                      "logs app {name} -n {namespace} --timestamps"
                    ],
                    options: {
                      namespace: namespace_opt,
                      follow: { type: :boolean, desc: "Follow log output" },
                      tail: { type: :numeric, desc: "Number of lines from end" },
                      timestamps: { type: :boolean, desc: "Show timestamps" }
                    },
                    dispatch: {
                      method: :logs,
                      params: [:name],
                      named_params: {
                        namespace: :namespace,
                        follow: :follow,
                        tail: :tail,
                        timestamps: :timestamps
                      },
                      namespace_handling: :required
                    }
                  },
                  pull: {
                    description: "Pull latest images without restarting",
                    usage: [ "pull app {name} -n {namespace}" ],
                    options: { namespace: namespace_opt },
                    dispatch: {
                      method: :pull,
                      params: [:name],
                      named_params: { namespace: :namespace },
                      namespace_handling: :required
                    }
                  },
                  describe: {
                    description: "Show running status of app containers",
                    usage: [ "describe app {name} -n {namespace}" ],
                    options: { namespace: namespace_opt },
                    dispatch: {
                      method: :describe,
                      params: [:name],
                      named_params: { namespace: :namespace },
                      namespace_handling: :required
                    }
                  }
                })
    end

    # Import operation - converts docker-compose to Walheim App manifest

    def import(namespace:, name:, compose_manifest:)
      # Check if app already exists
      if resource_exists?(namespace, name)
        warn "Error: app '#{name}' already exists in namespace '#{namespace}'"
        warn "Use 'whctl delete app #{name} -n #{namespace}' to remove it first"
        exit 1
      end

      # Convert docker-compose to Walheim App manifest
      app_manifest = {
        "apiVersion" => "walheim/v1alpha1",
        "kind" => "App",
        "metadata" => {
          "name" => name,
          "namespace" => namespace
        },
        "spec" => {
          "compose" => compose_manifest
        }
      }

      # Convert to YAML string
      manifest_yaml = YAML.dump(app_manifest)

      # Call create with the converted manifest
      create(namespace: namespace, name: name, manifest: manifest_yaml)
    end

    # Lifecycle operations (controller hooks)

    def start(namespace:, name:)
      # Load app manifest (.app.yaml)
      app_manifest = load_app_manifest(namespace, name)

      # Generate final docker-compose.yml with injected envs
      generate_compose_file(namespace, name, app_manifest)

      # Sync files to remote
      result = @syncer.sync(namespace: namespace, kind: "apps", name: name)

      # Run docker compose up
      remote_host = result[:username] ? "#{result[:username]}@#{result[:hostname]}" : result[:hostname]
      puts "Executing 'docker compose up -d' on #{remote_host} in #{result[:remote_dir]}"
      ssh_command = "ssh #{remote_host} 'cd #{result[:remote_dir]} && docker compose up -d --remove-orphans'"
      compose_result = system(ssh_command)

      unless compose_result
        warn "Error: docker compose up failed"
        exit 1
      end

      puts "Successfully started app '#{name}' in namespace '#{namespace}'"
    end

    def pause(namespace:, name:)
      # Get namespace config
      namespace_config = load_namespace_config(namespace)
      username = namespace_config["username"]
      hostname = namespace_config["hostname"]

      remote_host = username ? "#{username}@#{hostname}" : hostname
      remote_dir = "/data/walheim/apps/#{name}"

      # Check if remote directory exists (for idempotent deletes)
      check_command = "ssh #{remote_host} 'test -d #{remote_dir}'"
      dir_exists = system(check_command)

      unless dir_exists
        puts "App '#{name}' not found on #{remote_host} (already stopped or never deployed)"
        return
      end

      puts "Pausing app '#{name}' on #{remote_host}"
      ssh_command = "ssh #{remote_host} 'cd #{remote_dir} && docker compose down'"
      result = system(ssh_command)

      unless result
        warn "Error: docker compose down failed"
        exit 1
      end

      puts "Successfully paused app '#{name}' in namespace '#{namespace}'"
    end

    def stop(namespace:, name:)
      # First pause (docker compose down)
      pause(namespace: namespace, name: name)

      # Then remove files from remote
      namespace_config = load_namespace_config(namespace)
      username = namespace_config["username"]
      hostname = namespace_config["hostname"]

      remote_host = username ? "#{username}@#{hostname}" : hostname
      remote_dir = "/data/walheim/apps/#{name}"

      puts "Removing files from #{remote_host}:#{remote_dir}"
      ssh_command = "ssh #{remote_host} 'rm -rf #{remote_dir}'"
      result = system(ssh_command)

      unless result
        warn "Error: failed to remove remote files"
        exit 1
      end

      puts "Successfully stopped app '#{name}' in namespace '#{namespace}'"
    end

    def logs(namespace:, name:, follow: false, tail: nil, timestamps: false)
      # Get namespace config
      namespace_config = load_namespace_config(namespace)
      username = namespace_config["username"]
      hostname = namespace_config["hostname"]

      remote_host = username ? "#{username}@#{hostname}" : hostname
      remote_dir = "/data/walheim/apps/#{name}"

      # Check if remote directory exists
      check_command = "ssh #{remote_host} 'test -d #{remote_dir}'"
      dir_exists = system(check_command)

      unless dir_exists
        warn "Error: app '#{name}' not found on #{remote_host}"
        exit 1
      end

      # Build docker compose logs command with options
      logs_cmd = "docker compose logs"
      logs_cmd += " --follow" if follow
      logs_cmd += " --tail #{tail}" if tail
      logs_cmd += " --timestamps" if timestamps

      # Execute logs command (this will stream output to terminal)
      ssh_command = "ssh #{remote_host} 'cd #{remote_dir} && #{logs_cmd}'"

      # Use exec instead of system to replace current process
      # This allows proper signal handling (Ctrl+C) for --follow mode
      exec(ssh_command)
    end

    def pull(namespace:, name:)
      # Get namespace config
      namespace_config = load_namespace_config(namespace)
      username = namespace_config["username"]
      hostname = namespace_config["hostname"]

      remote_host = username ? "#{username}@#{hostname}" : hostname
      remote_dir = "/data/walheim/apps/#{name}"

      # Check if remote directory exists
      check_command = "ssh #{remote_host} 'test -d #{remote_dir}'"
      dir_exists = system(check_command)

      unless dir_exists
        warn "Error: app '#{name}' not found on #{remote_host}"
        warn "Deploy the app first using 'whctl apply app #{name} -n #{namespace}'"
        exit 1
      end

      # Pull latest images
      puts "Pulling latest images for '#{name}' on #{remote_host}"
      ssh_command = "ssh #{remote_host} 'cd #{remote_dir} && docker compose pull'"
      result = system(ssh_command)

      unless result
        warn "Error: docker compose pull failed"
        exit 1
      end

      puts "Successfully pulled latest images for app '#{name}' in namespace '#{namespace}'"
      puts "Use 'whctl start app #{name} -n #{namespace}' to apply the pulled images"
    end

    def describe(namespace:, name:)
      # Get namespace config
      namespace_config = load_namespace_config(namespace)
      username = namespace_config["username"]
      hostname = namespace_config["hostname"]

      remote_host = username ? "#{username}@#{hostname}" : hostname
      remote_dir = "/data/walheim/apps/#{name}"

      # Check if remote directory exists
      check_command = "ssh #{remote_host} 'test -d #{remote_dir}'"
      dir_exists = system(check_command)

      unless dir_exists
        warn "Error: app '#{name}' not found on #{remote_host}"
        warn "Deploy the app first using 'whctl apply app #{name} -n #{namespace}'"
        exit 1
      end

      # Display container status using docker compose ps
      puts "Status of '#{name}' on #{remote_host}:\n\n"

      # Get container status
      ps_command = "ssh #{remote_host} 'cd #{remote_dir} && docker compose ps'"
      system(ps_command)

      puts "\n"

      # Get resource usage for running containers
      stats_command = "ssh #{remote_host} 'cd #{remote_dir} && docker compose ps -q | xargs -r docker stats --no-stream --format \"table {{.Name}}\\t{{.CPUPerc}}\\t{{.MemUsage}}\\t{{.NetIO}}\\t{{.BlockIO}}\"'"

      puts "Resource Usage:"
      stats_result = system(stats_command)

      unless stats_result
        puts "(No running containers or unable to fetch stats)"
      end
    end

    private

    def load_app_manifest(namespace, name)
      app_dir = File.join(@namespaces_dir, namespace, "apps", name)
      app_yaml_path = File.join(app_dir, ".app.yaml")

      unless File.exist?(app_yaml_path)
        warn "Error: No app manifest found at #{app_yaml_path}"
        warn "Use 'whctl import' to convert docker-compose.yml to Walheim App format"
        exit 1
      end

      manifest = YAML.load_file(app_yaml_path)

      # Validate structure
      validate_k8s_manifest(manifest, namespace, name)

      {
        metadata: manifest["metadata"],
        env_from: manifest["spec"]["envFrom"] || [],
        env: manifest["spec"]["env"] || [],
        compose: manifest["spec"]["compose"]
      }
    end

    def validate_k8s_manifest(manifest, namespace, name)
      # Check required top-level fields
      unless manifest["apiVersion"] == "walheim/v1alpha1"
        warn "Error: apiVersion must be 'walheim/v1alpha1', got '#{manifest['apiVersion']}'"
        exit 1
      end

      unless manifest["kind"] == "App"
        warn "Error: kind must be 'App', got '#{manifest['kind']}'"
        exit 1
      end

      unless manifest["metadata"]
        warn "Error: metadata is required"
        exit 1
      end

      unless manifest["spec"]
        warn "Error: spec is required"
        exit 1
      end

      # Check metadata fields
      metadata_name = manifest["metadata"]["name"]
      unless metadata_name == name
        warn "Error: metadata.name '#{metadata_name}' must match directory name '#{name}'"
        exit 1
      end

      metadata_namespace = manifest["metadata"]["namespace"]
      unless metadata_namespace == namespace
        warn "Error: metadata.namespace '#{metadata_namespace}' must match parent namespace '#{namespace}'"
        exit 1
      end

      # Check spec.compose exists
      return if manifest["spec"]["compose"]

      warn "Error: spec.compose is required"
      exit 1
    end

    def generate_compose_file(namespace, name, app_manifest)
      app_dir = File.join(@namespaces_dir, namespace, "apps", name)
      compose_path = File.join(app_dir, "docker-compose.yml")

      # Start with base compose content
      compose_content = deep_copy(app_manifest[:compose])

      # Inject Walheim metadata labels (first, so it's clear these are managed)
      compose_content = inject_walheim_labels(compose_content, namespace, name)

      # Process envFrom and inject into compose (lower precedence)
      unless app_manifest[:env_from].empty?
        puts "Processing envFrom..."
        compose_content = inject_env_from(compose_content, app_manifest[:env_from], namespace)
      end

      # Process env and inject into compose (higher precedence)
      unless app_manifest[:env].empty?
        puts "Processing env..."
        compose_content = inject_env(compose_content, app_manifest[:env])
      end

      # Write generated docker-compose.yml
      File.write(compose_path, YAML.dump(compose_content))
      puts "Generated docker-compose.yml at #{compose_path}"
    end

    def inject_walheim_labels(compose, namespace, name)
      # Process each service and inject Walheim metadata labels
      compose["services"]&.each_value do |service_config|
        service_config["labels"] ||= []

        # Define Walheim metadata labels (stable labels only to avoid unnecessary restarts)
        walheim_labels = [
          "walheim.managed=true",
          "walheim.namespace=#{namespace}",
          "walheim.app=#{name}"
        ]

        # Inject labels (handle both array and hash formats)
        if service_config["labels"].is_a?(Array)
          # Remove any existing walheim.* labels first to avoid duplicates
          service_config["labels"].reject! do |label|
            label.to_s.start_with?("walheim.managed=", "walheim.namespace=", "walheim.app=")
          end
          # Add new labels
          service_config["labels"].concat(walheim_labels)
        else
          # Hash format
          service_config["labels"]["walheim.managed"] = "true"
          service_config["labels"]["walheim.namespace"] = namespace
          service_config["labels"]["walheim.app"] = name
        end
      end

      compose
    end

    def inject_env_from(compose, env_from_list, namespace)
      return compose if env_from_list.empty?

      # Process each service
      compose["services"]&.each do |service_name, service_config|
        service_config["environment"] ||= {}
        service_config["labels"] ||= []

        # Convert array-style to hash if needed
        if service_config["environment"].is_a?(Array)
          service_config["environment"] = array_env_to_hash(service_config["environment"])
        end

        # Track total injected for this service
        total_injected = 0

        # Inject from each envFrom source
        env_from_list.each do |source|
          # Check if this service should receive injections from this source
          service_names = source["serviceNames"]
          next if service_names && !service_names.empty? && !service_names.include?(service_name)

          if source["secretRef"]
            secret_name = source["secretRef"]["name"]
            injected_keys = inject_from_secret(service_config["environment"], secret_name, namespace)

            # Add tracking label if any keys were injected
            if injected_keys.any?
              add_tracking_label(service_config["labels"], "walheim.injected-env.secret.#{secret_name}", injected_keys)
              puts "  #{service_name}: Injected #{injected_keys.size} variable(s) from secret #{secret_name}: #{injected_keys.join(', ')}"
            end

            total_injected += injected_keys.size
          elsif source["configMapRef"]
            configmap_name = source["configMapRef"]["name"]
            injected_keys = inject_from_configmap(service_config["environment"], configmap_name, namespace)

            # Add tracking label if any keys were injected
            if injected_keys.any?
              add_tracking_label(service_config["labels"], "walheim.injected-env.configmap.#{configmap_name}",
                                 injected_keys)
              puts "  #{service_name}: Injected #{injected_keys.size} variable(s) from configmap #{configmap_name}: #{injected_keys.join(', ')}"
            end

            total_injected += injected_keys.size
          end
        end
      end

      compose
    end

    def array_env_to_hash(env_array)
      env_hash = {}
      env_array.each do |env_line|
        if env_line.include?("=")
          key, value = env_line.split("=", 2)
          env_hash[key] = value
        elsif env_line.is_a?(Hash)
          env_hash.merge!(env_line)
        end
      end
      env_hash
    end

    def inject_from_secret(environment, secret_name, namespace)
      secret_data = load_secret_data(namespace, secret_name)
      injected_keys = []

      secret_data.each do |key, value|
        # Skip if key already exists (existing env vars take precedence)
        next unless environment[key].nil?

        environment[key] = value
        injected_keys << key
      end

      injected_keys
    end

    def inject_from_configmap(environment, configmap_name, namespace)
      configmap_data = load_configmap_data(namespace, configmap_name)
      injected_keys = []

      configmap_data.each do |key, value|
        # Skip if key already exists (existing env vars take precedence)
        next unless environment[key].nil?

        environment[key] = value
        injected_keys << key
      end

      injected_keys
    end

    def add_tracking_label(labels, label_key, injected_keys)
      label_value = injected_keys.join(",")

      # Add label (handle both array and hash formats)
      if labels.is_a?(Array)
        labels << "#{label_key}=#{label_value}"
      else
        labels[label_key] = label_value
      end
    end

    def inject_env(compose, env_list)
      return compose if env_list.empty?

      # Process each service
      compose["services"]&.each do |service_name, service_config|
        service_config["environment"] ||= {}
        service_config["labels"] ||= []

        # Convert array-style to hash if needed
        if service_config["environment"].is_a?(Array)
          service_config["environment"] = array_env_to_hash(service_config["environment"])
        end

        # Track which keys were set by spec.env
        injected_keys = []

        # Process each env entry
        env_list.each do |env_entry|
          # Check if this service should receive this env var
          service_names = env_entry["serviceNames"]
          next if service_names && !service_names.empty? && !service_names.include?(service_name)

          var_name = env_entry["name"]
          var_value = env_entry["value"]

          # Perform variable substitution using current environment
          substituted_value = substitute_variables(var_value, service_config["environment"])

          # Always overwrite (highest precedence)
          service_config["environment"][var_name] = substituted_value
          injected_keys << var_name
        end

        # Add tracking label if any keys were set
        if injected_keys.any?
          add_tracking_label(service_config["labels"], "walheim.injected-env.override", injected_keys)
          puts "  #{service_name}: Set #{injected_keys.size} variable(s) from spec.env: #{injected_keys.join(', ')}"
        end
      end

      compose
    end

    def substitute_variables(value, environment)
      # Replace ${VAR_NAME} or $VAR_NAME with values from environment hash
      # Supports uppercase letters, numbers, and underscores
      value.to_s.gsub(/\$\{([A-Z_][A-Z0-9_]*)\}|\$([A-Z_][A-Z0-9_]*)/) do
        var_name = Regexp.last_match(1) || Regexp.last_match(2)
        environment[var_name] || "${#{var_name}}" # Keep original if not found
      end
    end

    def load_configmap_data(namespace, configmap_name)
      require "base64"

      configmap_path = File.join(@namespaces_dir, namespace, "configmaps", configmap_name, "configmap.yaml")

      unless File.exist?(configmap_path)
        warn "Error: configmap '#{configmap_name}' not found at #{configmap_path}"
        exit 1
      end

      configmap = YAML.load_file(configmap_path)

      # Extract data (plaintext only for configmaps)
      configmap["data"] || {}
    end

    def deep_copy(obj)
      Marshal.load(Marshal.dump(obj))
    end

    def manifest_filename
      ".app.yaml"
    end

    def validate_manifest(manifest, namespace, name)
      manifest_hash = YAML.safe_load(manifest)
      validate_k8s_manifest(manifest_hash, namespace, name) if manifest_hash["kind"] == "App"
    end

    def load_secret_data(namespace, secret_name)
      require "base64"

      secret_path = File.join(@namespaces_dir, namespace, "secrets", secret_name, "secret.yaml")

      unless File.exist?(secret_path)
        warn "Error: secret '#{secret_name}' not found at #{secret_path}"
        exit 1
      end

      secret = YAML.load_file(secret_path)

      # Extract data (base64-encoded) and stringData (plaintext)
      data = secret["data"] || {}
      string_data = secret["stringData"] || {}

      # Decode base64 data
      decoded_data = {}
      data.each do |key, value|
        decoded_data[key] = Base64.decode64(value.to_s)
      end

      # Merge decoded data and stringData (stringData takes precedence)
      decoded_data.merge(string_data)
    end

    def load_namespace_config(namespace)
      config_path = File.join(@namespaces_dir, namespace, ".namespace.yaml")

      unless File.exist?(config_path)
        warn "Error: namespace config '#{config_path}' not found"
        exit 1
      end

      YAML.load_file(config_path)
    end
  end
end

# Register handler
info = Resources::Apps.kind_info
Walheim::HandlerRegistry.register(
  kind: info[:plural],
  plural: info[:plural],
  singular: info[:singular],
  handler_class: Resources::Apps,
  aliases: info[:aliases] || []
)
