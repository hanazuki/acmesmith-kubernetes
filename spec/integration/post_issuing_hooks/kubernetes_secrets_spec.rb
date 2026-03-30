require 'base64'
require 'acmesmith/post_issuing_hooks/kubernetes_secrets'
require 'acmesmith/certificate'
require 'acmesmith/kubernetes'
require_relative '../spec_helper'

RSpec.describe Acmesmith::PostIssuingHooks::KubernetesSecrets do
  include Acmesmith::Kubernetes

  let(:namespace) { 'default' }
  let(:secret_name) { "tls-test-#{SecureRandom.hex(4)}" }
  let(:hook) do
    described_class.new(
      namespace: namespace,
      name: secret_name,
      labels: { 'app' => 'test' },
      annotations: { 'managed-by' => 'acmesmith' },
    )
  end

  after do
    k8s = build_kubernetes_client
    begin
      k8s.delete_secret(secret_name, namespace)
    rescue Kubeclient::HttpError => e
      raise unless e.error_code == 404
    end
  end

  let(:certificate) { build_test_certificate }

  describe '#execute (via #run)' do
    it 'creates a TLS Secret on first call with correct tls.crt and tls.key' do
      hook.run(certificate: certificate)

      k8s = build_kubernetes_client
      secret = k8s.get_secret(secret_name, namespace)

      expect(secret.type).to eq('kubernetes.io/tls')
      expect(Base64.strict_decode64(secret.data['tls.crt'])).to eq(certificate.fullchain)
      expect(Base64.strict_decode64(secret.data['tls.key'])).to eq(certificate.private_key.export)
    end

    it 'updates the existing Secret on second call with new certificate data' do
      hook.run(certificate: certificate)

      new_certificate = build_test_certificate
      hook.run(certificate: new_certificate)

      k8s = build_kubernetes_client
      secret = k8s.get_secret(secret_name, namespace)

      expect(Base64.strict_decode64(secret.data['tls.crt'])).to eq(new_certificate.fullchain)
      expect(Base64.strict_decode64(secret.data['tls.key'])).to eq(new_certificate.private_key.export)
    end
  end
end
