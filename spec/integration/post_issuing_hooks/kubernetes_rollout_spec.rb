require 'acmesmith/post_issuing_hooks/kubernetes_rollout'
require 'acmesmith/certificate'
require 'acmesmith/kubernetes'
require_relative '../spec_helper'

RSpec.describe Acmesmith::PostIssuingHooks::KubernetesRollout do
  include Acmesmith::Kubernetes

  RE_DATETIME = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/

  let(:namespace) { 'default' }
  let(:deployment_name) { "rollout-test-#{SecureRandom.hex(4)}" }
  let(:hook) do
    described_class.new(namespace: namespace, kind: 'Deployment', name: deployment_name)
  end

  let!(:apps) { build_kubernetes_client('apps/v1') }

  def create_deployment(name, extra_labels: {})
    deployment = Kubeclient::Resource.new(
      metadata: { name: name, namespace: namespace, labels: { app: name }.merge(extra_labels) },
      spec: {
        selector: { matchLabels: { app: name } },
        template: {
          metadata: { labels: { app: name } },
          spec: { containers: [{ name: 'pause', image: 'registry.k8s.io/pause:3.9' }] },
        },
      },
    )
    apps.create_deployment(deployment)
  end

  before do
    create_deployment(deployment_name)
  end

  after do
    begin
      apps.delete_deployment(deployment_name, namespace)
    rescue Kubeclient::HttpError => e
      raise unless e.error_code == 404
    end
  end

  let(:certificate) { build_test_certificate }

  describe '#execute (via #run)' do
    context 'when the resource does not exist' do
      let(:hook) { described_class.new(namespace: namespace, kind: 'Deployment', name: 'nonexistent') }

      it 'raises without if_exists' do
        expect { hook.run(certificate: certificate) }.to raise_error(Kubeclient::HttpError)
      end

      context 'with if_exists: true' do
        let(:hook) { described_class.new(namespace: namespace, kind: 'Deployment', name: 'nonexistent', if_exists: true) }

        it 'does not raise' do
          expect { hook.run(certificate: certificate) }.not_to raise_error
        end
      end
    end

    it 'patches the restartedAt annotation on first call' do
      expect { hook.run(certificate: certificate) }
        .to change { apps.get_deployment(deployment_name, namespace).spec.template.metadata.annotations&.[]('kubectl.kubernetes.io/restartedAt') }.from(nil).to(RE_DATETIME)
    end

    it 'updates the restartedAt annotation to a newer timestamp on second call' do
      hook.run(certificate: certificate)
      sleep 1
      expect { hook.run(certificate: build_test_certificate) }
        .to change { apps.get_deployment(deployment_name, namespace).spec.template.metadata.annotations&.[]('kubectl.kubernetes.io/restartedAt') }.from(RE_DATETIME).to(RE_DATETIME)
    end
  end

  describe '#execute with selector (via #run)' do
    let(:label_key) { 'rollout-test-group' }
    let(:label_value) { SecureRandom.hex(4) }
    let(:selector) { "#{label_key}=#{label_value}" }
    let(:other_deployment_name) { "rollout-test-#{SecureRandom.hex(4)}" }

    before do
      create_deployment(other_deployment_name, extra_labels: { label_key => label_value })
    end

    after do
      begin
        apps.delete_deployment(other_deployment_name, namespace)
      rescue Kubeclient::HttpError => e
        raise unless e.error_code == 404
      end
    end

    context 'with selector matching multiple deployments' do
      let(:hook) { described_class.new(namespace: namespace, kind: 'Deployment', selector: selector) }

      before do
        # Also label the main deployment so both are selected
        apps.patch_deployment(deployment_name, { metadata: { labels: { label_key => label_value } } }, namespace)
      end

      it 'patches restartedAt on all matching deployments' do
        hook.run(certificate: certificate)
        [deployment_name, other_deployment_name].each do |name|
          annotation = apps.get_deployment(name, namespace).spec.template.metadata.annotations&.[]('kubectl.kubernetes.io/restartedAt')
          expect(annotation).to match(RE_DATETIME)
        end
      end
    end

    context 'with selector matching no resources' do
      let(:hook) { described_class.new(namespace: namespace, kind: 'Deployment', selector: "#{label_key}=no-match") }

      it 'does not raise' do
        expect { hook.run(certificate: certificate) }.not_to raise_error
      end
    end
  end
end
