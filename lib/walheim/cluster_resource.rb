# frozen_string_literal: true

require_relative 'resource'

module Walheim
  # ClusterResource represents resources that are cluster-scoped (not namespaced)
  # Examples: Namespaces themselves
  # These resources typically live at the top level (e.g., namespaces/{name}/)
  class ClusterResource < Resource
    # Get operation for cluster-scoped resources
    # Returns list of all resources (no namespace filtering)
    def get(name: nil)
      if name.nil?
        # List all cluster resources
        list_all
      else
        # Get single cluster resource
        get_single_resource(name)
      end
    end

    # Create a cluster-scoped resource
    def create(name:, manifest:)
      # Validate manifest if validator exists
      validate_manifest(manifest, name) if respond_to?(:validate_manifest, true)

      # Create directory structure
      ensure_resource_dir(name)

      # Write manifest
      write_manifest(name, manifest)

      puts "Created #{self.class.kind_info[:singular]} '#{name}'"

      # POST-CREATE HOOK
      trigger_hook(:post_create, name: name)
    end

    # Update a cluster-scoped resource
    def update(name:, manifest:)
      # Validate manifest if validator exists
      validate_manifest(manifest, name) if respond_to?(:validate_manifest, true)

      # Write manifest (overwrite)
      write_manifest(name, manifest)

      puts "Updated #{self.class.kind_info[:singular]} '#{name}'"

      # POST-UPDATE HOOK
      trigger_hook(:post_update, name: name)
    end

    # Delete a cluster-scoped resource
    def delete(name:)
      unless resource_exists?(name)
        warn "Error: #{self.class.kind_info[:singular]} '#{name}' not found"
        exit 1
      end

      # PRE-DELETE HOOK
      trigger_hook(:pre_delete, name: name)

      # Delete from filesystem
      remove_resource_dir(name)

      puts "Deleted #{self.class.kind_info[:singular]} '#{name}'"
    end

    # Apply operation - create or update
    def apply(name:, manifest_source: nil)
      manifest_data = if manifest_source
        File.read(manifest_source)
      else
        read_manifest_from_db(name)
      end

      if resource_exists?(name)
        update(name: name, manifest: manifest_data)
      else
        create(name: name, manifest: manifest_data)
      end
    end

    private

    def get_single_resource(name)
      unless resource_exists?(name)
        warn "Error: #{self.class.kind_info[:singular]} '#{name}' not found"
        exit 1
      end

      manifest_path = File.join(resource_dir(name), manifest_filename)
      manifest_content = File.read(manifest_path)
      manifest_data = YAML.load(manifest_content)

      # Compute summary fields
      summary = {}
      self.class.summary_fields.each do |field_name, compute_fn|
        summary[field_name] = compute_fn.call(manifest_data)
      end

      {
        name: name,
        manifest: manifest_data,
        summary: summary
      }
    end

    def list_all
      base_dir = File.join(@data_dir, self.class.kind_info[:plural])
      return [] unless Dir.exist?(base_dir)

      # Find all resource directories
      resource_names = find_resource_names

      # Return array of resource hashes
      resource_names.map do |name|
        get_single_resource(name)
      end
    end

    # Override in subclasses to customize how resources are discovered
    def find_resource_names
      base_dir = File.join(@data_dir, self.class.kind_info[:plural])
      Dir.entries(base_dir)
         .select { |entry| File.directory?(File.join(base_dir, entry)) && !entry.start_with?('.') }
         .select { |entry| File.exist?(File.join(base_dir, entry, manifest_filename)) }
         .sort
    end

    # Path to resource directory (cluster resources: {data_dir}/{kind_plural}/{name}/)
    # For namespaces: {data_dir}/namespaces/{name}/
    # For appsets: {data_dir}/appsets/{name}/
    def resource_dir(name)
      File.join(@data_dir, self.class.kind_info[:plural], name)
    end

    def resource_exists?(name)
      manifest_path = File.join(resource_dir(name), manifest_filename)
      File.exist?(manifest_path)
    end

    def ensure_resource_dir(name)
      FileUtils.mkdir_p(resource_dir(name))
    end

    def write_manifest(name, manifest)
      path = File.join(resource_dir(name), manifest_filename)
      File.write(path, manifest)
    end

    def read_manifest_from_db(name)
      path = File.join(resource_dir(name), manifest_filename)
      unless File.exist?(path)
        warn "Error: No manifest found at #{path}"
        warn "Use 'whctl apply -f <file>' to create from a manifest file"
        exit 1
      end
      File.read(path)
    end

    def remove_resource_dir(name)
      FileUtils.rm_rf(resource_dir(name))
    end
  end
end
