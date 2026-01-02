# frozen_string_literal: true

require_relative 'walheim/version'
require_relative 'walheim/config'
require_relative 'walheim/handler_registry'
require_relative 'walheim/resource'
require_relative 'walheim/cluster_resource'
require_relative 'walheim/namespaced_resource'
require_relative 'walheim/sync'

# Load resource handlers
require_relative 'walheim/resources/namespaces'
require_relative 'walheim/resources/apps'
require_relative 'walheim/resources/secrets'
require_relative 'walheim/resources/configmaps'

# Load CLI
require_relative 'walheim/cli'

module Walheim
  class Error < StandardError; end
end
