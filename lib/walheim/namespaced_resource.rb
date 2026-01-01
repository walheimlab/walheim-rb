# frozen_string_literal: true

require_relative 'resource'

module Walheim
  # NamespacedResource represents resources that are scoped to a namespace
  # Examples: Apps, Secrets, ConfigMaps
  # These resources live under namespaces/{namespace}/{kind}/{name}/
  class NamespacedResource < Resource
    # CRUD operations for namespace-scoped resources

    def apply(namespace:, name:, manifest_source: nil)
      manifest_data = if manifest_source
        File.read(manifest_source)
      else
        read_manifest_from_db(namespace, name)
      end

      if resource_exists?(namespace, name)
        update(namespace: namespace, name: name, manifest: manifest_data)
      else
        create(namespace: namespace, name: name, manifest: manifest_data)
      end
    end

    def create(namespace:, name:, manifest:)
      # Validate manifest if validator exists
      validate_manifest(manifest, namespace, name) if respond_to?(:validate_manifest, true)

      # Create directory structure
      ensure_resource_dir(namespace, name)

      # Write manifest to DB
      write_manifest(namespace, name, manifest)

      puts "Created #{self.class.kind_info[:singular]} '#{name}' in namespace '#{namespace}'"

      # POST-CREATE HOOK
      trigger_hook(:post_create, namespace: namespace, name: name)
    end

    def update(namespace:, name:, manifest:)
      # Validate manifest if validator exists
      validate_manifest(manifest, namespace, name) if respond_to?(:validate_manifest, true)

      # Write manifest to DB (overwrite)
      write_manifest(namespace, name, manifest)

      puts "Updated #{self.class.kind_info[:singular]} '#{name}' in namespace '#{namespace}'"

      # POST-UPDATE HOOK
      trigger_hook(:post_update, namespace: namespace, name: name)
    end

    def delete(namespace:, name:)
      unless resource_exists?(namespace, name)
        warn "Error: #{self.class.kind_info[:singular]} '#{name}' not found"
        exit 1
      end

      # PRE-DELETE HOOK
      trigger_hook(:pre_delete, namespace: namespace, name: name)

      # Delete from DB
      remove_resource_dir(namespace, name)

      puts "Deleted #{self.class.kind_info[:singular]} '#{name}' from namespace '#{namespace}'"
    end

    def get(namespace:, name: nil)
      if namespace.nil? && name.nil?
        # List all resources across all namespaces
        list_all_namespaces
      elsif namespace && name.nil?
        # List resources in a single namespace
        list_single_namespace(namespace)
      elsif namespace && name
        # Get single resource
        get_single_resource(namespace, name)
      else
        raise ArgumentError, 'namespace is required when name is specified'
      end
    end

    private

    def get_single_resource(namespace, name)
      unless resource_exists?(namespace, name)
        warn "Error: #{self.class.kind_info[:singular]} '#{name}' not found in namespace '#{namespace}'"
        exit 1
      end

      manifest_path = File.join(resource_dir(namespace, name), manifest_filename)
      manifest_content = File.read(manifest_path)
      manifest_data = YAML.load(manifest_content)

      # Compute summary fields
      summary = {}
      self.class.summary_fields.each do |field_name, compute_fn|
        summary[field_name] = compute_fn.call(manifest_data)
      end

      {
        namespace: namespace,
        name: name,
        manifest: manifest_data,
        summary: summary
      }
    end

    def resource_dir(namespace, name)
      File.join(@namespaces_dir, namespace, self.class.kind_info[:plural], name)
    end

    def resource_exists?(namespace, name)
      manifest_path = File.join(resource_dir(namespace, name), manifest_filename)
      File.exist?(manifest_path)
    end

    def ensure_resource_dir(namespace, name)
      FileUtils.mkdir_p(resource_dir(namespace, name))
    end

    def write_manifest(namespace, name, manifest)
      path = File.join(resource_dir(namespace, name), manifest_filename)
      File.write(path, manifest)
    end

    def read_manifest_from_db(namespace, name)
      path = File.join(resource_dir(namespace, name), manifest_filename)
      unless File.exist?(path)
        warn "Error: No manifest found at #{path}"
        warn "Use 'whctl apply -f <file>' to create from a manifest file"
        exit 1
      end
      File.read(path)
    end

    def remove_resource_dir(namespace, name)
      FileUtils.rm_rf(resource_dir(namespace, name))
    end

    def list_single_namespace(namespace)
      namespace_path = File.join(@namespaces_dir, namespace)

      unless Dir.exist?(namespace_path)
        warn "Error: namespace '#{namespace}' not found"
        exit 1
      end

      resources_path = File.join(namespace_path, self.class.kind_info[:plural])
      return [] unless Dir.exist?(resources_path)

      # Find all resource directories
      resource_names = Dir.entries(resources_path)
                          .select { |entry| File.directory?(File.join(resources_path, entry)) && !entry.start_with?('.') }
                          .sort

      # Return array of manifest hashes
      resource_names.map do |name|
        get_single_resource(namespace, name)
      end
    end

    def list_all_namespaces
      return [] unless Dir.exist?(@namespaces_dir)

      # Find all namespaces
      namespace_names = Dir.entries(@namespaces_dir)
                           .select { |entry| File.directory?(File.join(@namespaces_dir, entry)) && !entry.start_with?('.') }
                           .select { |entry| File.exist?(File.join(@namespaces_dir, entry, '.namespace.yaml')) }
                           .sort

      # Collect all resources from all namespaces
      all_resources = []
      namespace_names.each do |namespace|
        resources_path = File.join(@namespaces_dir, namespace, self.class.kind_info[:plural])
        next unless Dir.exist?(resources_path)

        resource_names = Dir.entries(resources_path)
                            .select { |entry| File.directory?(File.join(resources_path, entry)) && !entry.start_with?('.') }
                            .sort

        resource_names.each do |resource_name|
          all_resources << get_single_resource(namespace, resource_name)
        end
      end

      all_resources.sort_by { |resource| [resource[:namespace], resource[:name]] }
    end
  end
end
