require 'acmesmith/post_issuing_hooks/base'
require 'acmesmith/kubernetes'
require 'time'

module Acmesmith
  module PostIssuingHooks
    class KubernetesRollout < Base
      include Acmesmith::Kubernetes

      SUPPORTED_KINDS = %w[Deployment StatefulSet DaemonSet].freeze
      RESTART_ANNOTATION = 'kubectl.kubernetes.io/restartedAt'

      def initialize(namespace: 'default', kind:, name:, if_exists: false)
        unless SUPPORTED_KINDS.include?(kind)
          raise ArgumentError, "Unsupported kind: #{kind}. Must be one of #{SUPPORTED_KINDS.join(', ')}"
        end

        @namespace = namespace
        @kind = kind
        @name = name
        @if_exists = if_exists
      end

      def execute
        patch = { spec: { template: { metadata: { annotations: { RESTART_ANNOTATION => Time.now.utc.iso8601 } } } } }

        begin
          case @kind
          when 'Deployment'
            apps_client.patch_deployment(@name, patch, @namespace)
          when 'StatefulSet'
            apps_client.patch_stateful_set(@name, patch, @namespace)
          when 'DaemonSet'
            apps_client.patch_daemon_set(@name, patch, @namespace)
          end
        rescue Kubeclient::HttpError => e
          raise unless @if_exists && e.error_code == 404
        end
      end

      private

      def apps_client
        @apps_client ||= build_kubernetes_client('apps/v1')
      end
    end
  end
end
