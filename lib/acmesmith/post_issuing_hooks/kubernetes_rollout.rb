require 'acmesmith/post_issuing_hooks/base'
require 'acmesmith/kubernetes'
require 'time'

module Acmesmith
  module PostIssuingHooks
    class KubernetesRollout < Base
      include Acmesmith::Kubernetes

      SUPPORTED_KINDS = %w[Deployment StatefulSet DaemonSet].freeze
      RESTART_ANNOTATION = 'kubectl.kubernetes.io/restartedAt'

      def initialize(namespace: 'default', kind:, name: nil, selector: nil, if_exists: false)
        unless SUPPORTED_KINDS.include?(kind)
          raise ArgumentError, "Unsupported kind: #{kind}. Must be one of #{SUPPORTED_KINDS.join(', ')}"
        end

        if selector
          raise TypeError, 'selector must be a String' unless selector.is_a?(String)
          raise ArgumentError, 'selector must not be empty' if selector.empty?
          raise ArgumentError, 'name and selector are mutually exclusive' if name
        else
          raise ArgumentError, 'name is required when selector is not specified' unless name
        end

        @namespace = namespace
        @kind = kind
        @name = name
        @selector = selector
        @if_exists = if_exists
      end

      def execute
        patch = { spec: { template: { metadata: { annotations: { RESTART_ANNOTATION => Time.now.utc.iso8601 } } } } }

        if @selector
          execute_by_selector(patch)
        else
          execute_by_name(patch)
        end
      end

      private

      def execute_by_name(patch)
        begin
          patch_resource(@kind, @name, patch)
        rescue Kubeclient::HttpError => e
          raise unless @if_exists && e.error_code == 404
        end
      end

      def execute_by_selector(patch)
        list_resources(@kind, @selector).each do |resource|
          patch_resource(@kind, resource.metadata.name, patch)
        end
      end

      def list_resources(kind, selector)
        case kind
        when 'Deployment'
          apps_client.get_deployments(namespace: @namespace, label_selector: selector)
        when 'StatefulSet'
          apps_client.get_stateful_sets(namespace: @namespace, label_selector: selector)
        when 'DaemonSet'
          apps_client.get_daemon_sets(namespace: @namespace, label_selector: selector)
        end
      end

      def patch_resource(kind, name, patch)
        case kind
        when 'Deployment'
          apps_client.patch_deployment(name, patch, @namespace)
        when 'StatefulSet'
          apps_client.patch_stateful_set(name, patch, @namespace)
        when 'DaemonSet'
          apps_client.patch_daemon_set(name, patch, @namespace)
        end
      end

      def apps_client
        @apps_client ||= build_kubernetes_client('apps/v1')
      end
    end
  end
end
