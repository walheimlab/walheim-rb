# frozen_string_literal: true

require "yaml"

module Walheim
  # LabelOperations provides label management functionality for all resource types
  # This module is used by the CLI label command
  module LabelOperations
    class << self
      # Set labels on a resource
      # label_specs: Array of strings like ["key1=value1", "key2=value2", "key3-"]
      def set_labels(data_dir:, kind:, name:, label_specs:, namespace: nil, overwrite: false)
        # Parse label specifications
        labels_to_set = {}
        labels_to_remove = []

        label_specs.each do |spec|
          if spec.end_with?("-")
            # Remove label (key-)
            labels_to_remove << spec[0..-2]
          elsif spec.include?("=")
            # Set label (key=value)
            key, value = spec.split("=", 2)
            validate_label_key(key)
            labels_to_set[key] = value
          else
            warn "Error: invalid label spec '#{spec}'. Use key=value to set or key- to remove"
            exit 1
          end
        end

        if labels_to_set.empty? && labels_to_remove.empty?
          warn "Error: no label changes specified"
          exit 1
        end

        # Load resource manifest
        manifest_path, manifest_data = load_resource_manifest(data_dir, kind, name, namespace)

        # Ensure metadata exists
        manifest_data["metadata"] ||= {}
        manifest_data["metadata"]["labels"] ||= {}
        current_labels = manifest_data["metadata"]["labels"]

        # Apply label changes
        labels_to_set.each do |key, value|
          if current_labels.key?(key) && !overwrite
            warn "Error: label '#{key}' already exists with value '#{current_labels[key]}'"
            warn "Use --overwrite to replace existing labels"
            exit 1
          end
          current_labels[key] = value
        end

        labels_to_remove.each do |key|
          unless current_labels.key?(key)
            warn "Warning: label '#{key}' not found, skipping removal"
          end
          current_labels.delete(key)
        end

        # Clean up empty labels hash
        manifest_data["metadata"].delete("labels") if current_labels.empty?

        # Write manifest back
        File.write(manifest_path, YAML.dump(manifest_data))

        # Output result
        resource_ref = namespace ? "#{kind}/#{name} -n #{namespace}" : "#{kind}/#{name}"
        puts "#{resource_ref} labeled"
      end

      # List labels on a resource
      def list_labels(data_dir:, kind:, name:, namespace: nil)
        _manifest_path, manifest_data = load_resource_manifest(data_dir, kind, name, namespace)

        labels = manifest_data.dig("metadata", "labels") || {}

        if labels.empty?
          puts "No labels."
        else
          # Print in kubectl style: key=value
          labels.each do |key, value|
            puts "#{key}=#{value}"
          end
        end
      end

      private

      def validate_label_key(key)
        # Basic validation: alphanumeric, dash, underscore, dot, slash
        # Kubectl allows: [a-z0-9A-Z._/-]+
        unless key.match?(/^[a-zA-Z0-9._\/-]+$/)
          warn "Error: invalid label key '#{key}'. Keys must contain only alphanumerics, '-', '_', '.', or '/'"
          exit 1
        end
      end

      def load_resource_manifest(data_dir, kind, name, namespace)
        # Look up handler for this kind
        handler_info = Walheim::HandlerRegistry.get(kind)
        unless handler_info
          warn "Error: unknown resource kind '#{kind}'"
          warn "Use 'whctl --help' to see available resource types"
          exit 1
        end

        handler_class = handler_info[:handler]
        handler = handler_class.new(data_dir: data_dir)

        # Determine manifest path based on resource type
        if handler.is_a?(Walheim::ClusterResource)
          # Cluster resource (e.g., namespace)
          if namespace
            warn "Error: '#{kind}' is a cluster-scoped resource and does not use -n flag"
            exit 1
          end

          manifest_path = get_cluster_manifest_path(data_dir, kind, name, handler)
        elsif handler.is_a?(Walheim::NamespacedResource)
          # Namespaced resource (e.g., app, secret)
          unless namespace
            warn "Error: '#{kind}' is a namespaced resource and requires -n namespace flag"
            exit 1
          end

          manifest_path = get_namespaced_manifest_path(data_dir, kind, name, namespace, handler)
        else
          warn "Error: unknown resource type for kind '#{kind}'"
          exit 1
        end

        unless File.exist?(manifest_path)
          resource_ref = namespace ? "#{kind} '#{name}' in namespace '#{namespace}'" : "#{kind} '#{name}'"
          warn "Error: #{resource_ref} not found"
          exit 1
        end

        manifest_data = YAML.load_file(manifest_path)
        [ manifest_path, manifest_data ]
      end

      def get_cluster_manifest_path(data_dir, _kind, name, handler)
        # Use handler's manifest_filename method
        manifest_filename = handler.send(:manifest_filename)
        File.join(data_dir, handler.class.kind_info[:plural], name, manifest_filename)
      end

      def get_namespaced_manifest_path(data_dir, _kind, name, namespace, handler)
        manifest_filename = handler.send(:manifest_filename)
        namespaces_dir = File.join(data_dir, "namespaces")
        File.join(namespaces_dir, namespace, handler.class.kind_info[:plural], name, manifest_filename)
      end
    end
  end
end
