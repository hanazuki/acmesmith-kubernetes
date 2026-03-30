require_relative 'kubernetes/version'

require 'kubeclient'

module Acmesmith
  module Kubernetes
    INCLUSTER_TOKEN = -'/var/run/secrets/kubernetes.io/serviceaccount/token'
    INCLUSTER_CA = -'/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'

    def build_kubernetes_client
      if kubeconfig = ENV['KUBECONFIG']
        config = Kubeclient::Config.read(kubeconfig)
        context = config.context
        Kubeclient::Client.new(
          context.api_endpoint, 'v1',
          ssl_options: context.ssl_options,
          auth_options: context.auth_options,
        )
      else
        host = ENV.fetch('KUBERNETES_SERVICE_HOST')
        port = ENV.fetch('KUBERNETES_SERVICE_PORT')
        endpoint = "https://#{host.include?(':') ? "[#{host}]" : host}:#{port}"
        Kubeclient::Client.new(
          endpoint, 'v1',
          auth_options: { bearer_token_file: INCLUSTER_TOKEN },
          ssl_options: { ca_file: INCLUSTER_CA },
        )
      end
    end
  end
end
