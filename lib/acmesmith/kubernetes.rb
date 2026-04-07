require_relative 'kubernetes/version'

require 'kubeclient'

module Acmesmith
  module Kubernetes
    INCLUSTER_TOKEN = -'/var/run/secrets/kubernetes.io/serviceaccount/token'
    INCLUSTER_CA = -'/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'

    def build_kubernetes_client(api_version = 'v1')
      if api_version.include?(?/)
        api, version =  api_version.split(?/, 2)
        path = "/apis/#{api}"
      else
        version = api_version
        path = ''
      end

      if kubeconfig = ENV['KUBECONFIG']
        config = Kubeclient::Config.read(kubeconfig)
        context = config.context
        endpoint = "#{context.api_endpoint}#{path}"
        Kubeclient::Client.new(
          endpoint, version,
          ssl_options: context.ssl_options,
          auth_options: context.auth_options,
        )
      else
        host = ENV.fetch('KUBERNETES_SERVICE_HOST')
        port = ENV.fetch('KUBERNETES_SERVICE_PORT')
        base = "https://#{host.include?(':') ? "[#{host}]" : host}:#{port}"
        endpoint = "#{base}#{path}"
        Kubeclient::Client.new(
          endpoint, version,
          auth_options: { bearer_token_file: INCLUSTER_TOKEN },
          ssl_options: { ca_file: INCLUSTER_CA },
        )
      end
    end
  end
end
