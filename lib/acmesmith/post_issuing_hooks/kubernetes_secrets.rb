require 'acmesmith/post_issuing_hooks/base'
require 'acmesmith/kubernetes'
require 'kubeclient'
require 'base64'

module Acmesmith
  module PostIssuingHooks
    class KubernetesSecrets < Base
      include Acmesmith::Kubernetes

      def initialize(namespace:, name:, labels: {}, annotations: {})
        @namespace = namespace
        @name = name
        @labels = labels
        @annotations = annotations
      end

      def execute
        tls_crt = Base64.strict_encode64(certificate.fullchain)
        tls_key = Base64.strict_encode64(certificate.private_key.export)

        secret_resource = Kubeclient::Resource.new(
          metadata: {
            name: @name,
            namespace: @namespace,
            labels: @labels,
            annotations: @annotations,
          },
          type: 'kubernetes.io/tls',
          data: {
            'tls.crt' => tls_crt,
            'tls.key' => tls_key,
          },
        )

        begin
          kubernetes_client.get_secret(@name, @namespace)
          kubernetes_client.patch_secret(
            @name,
            {
              metadata: {
                labels: @labels,
                annotations: @annotations,
              },
              data: {
                'tls.crt' => tls_crt,
                'tls.key' => tls_key,
              },
            },
            @namespace,
          )
        rescue Kubeclient::HttpError => e
          raise unless e.error_code == 404
          kubernetes_client.create_secret(secret_resource)
        end
      end

      private

      def kubernetes_client
        @kubernetes_client ||= build_kubernetes_client
      end
    end
  end
end
