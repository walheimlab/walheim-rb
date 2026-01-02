# frozen_string_literal: true

require 'terminal-table'
require 'yaml'

module Walheim
  module Helpers
    # Print resources table for namespaced resources
    def self.print_resources_table(result, all_namespaces, kind_name)
      if result.is_a?(Hash)
        # Single resource - print YAML
        puts YAML.dump(result[:manifest])
        return
      end

      if result.empty?
        puts all_namespaces ? "No #{kind_name} found" : "No #{kind_name} found in namespace"
        return
      end

      # Extract summary field names from first result
      summary_fields = result.first[:summary].keys

      # Build header row
      if all_namespaces
        headers = ['NAMESPACE', 'NAME'] + summary_fields.map(&:to_s).map(&:upcase)
      else
        headers = ['NAME'] + summary_fields.map(&:to_s).map(&:upcase)
      end

      # Build data rows
      rows = result.map do |resource|
        row = if all_namespaces
          [resource[:namespace], resource[:name]]
        else
          [resource[:name]]
        end

        # Add summary field values
        summary_values = summary_fields.map { |field| resource[:summary][field] || 'N/A' }
        row + summary_values
      end

      all_rows = [headers] + rows

      table = Terminal::Table.new do |t|
        t.rows = all_rows
        t.style = {
          border_x: '', border_y: '', border_i: '',
          padding_left: 0, padding_right: 3,
          border_top: false, border_bottom: false,
          all_separators: false
        }
      end

      puts table
    end

    # Print resources table for cluster resources
    def self.print_cluster_resources_table(result, kind_name)
      if result.is_a?(Hash)
        # Single resource - print YAML
        puts YAML.dump(result[:manifest])
        return
      end

      if result.empty?
        puts "No #{kind_name} found"
        return
      end

      # Extract summary field names from first result
      summary_fields = result.first[:summary].keys

      # Build header row (no NAMESPACE column for cluster resources)
      headers = ['NAME'] + summary_fields.map(&:to_s).map(&:upcase)

      # Build data rows
      rows = result.map do |resource|
        row = [resource[:name]]

        # Add summary field values
        summary_values = summary_fields.map { |field| resource[:summary][field] || 'N/A' }
        row + summary_values
      end

      all_rows = [headers] + rows

      table = Terminal::Table.new do |t|
        t.rows = all_rows
        t.style = {
          border_x: '', border_y: '', border_i: '',
          padding_left: 0, padding_right: 3,
          border_top: false, border_bottom: false,
          all_separators: false
        }
      end

      puts table
    end

    # Read YAML from file or stdin
    def self.read_yaml_input(file_path)
      if file_path == '-'
        # Read from stdin
        YAML.load(STDIN.read)
      else
        # Read from file
        YAML.load_file(file_path)
      end
    end
  end
end
