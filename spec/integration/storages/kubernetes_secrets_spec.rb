require 'acmesmith/storages/kubernetes_secrets'
require 'acmesmith/account_key'
require 'acmesmith/certificate'
require_relative '../spec_helper'

RSpec.describe Acmesmith::Storages::KubernetesSecrets do
  include Acmesmith::Kubernetes

  let(:instance_name) { "test-#{SecureRandom.hex(4)}" }
  let(:namespace) { 'default' }
  let(:name_prefix) { 'acmesmith-test-' }
  let(:storage) do
    described_class.new(
      instance: instance_name,
      namespace: namespace,
      name_prefix: name_prefix,
    )
  end

  after do
    k8s = build_kubernetes_client
    label_selector = "acmesmith-kubernetes.hanazuki.dev/instance=#{instance_name}"
    k8s.get_secrets(namespace: namespace, label_selector: label_selector).each do |secret|
      k8s.delete_secret(secret.metadata.name, namespace)
    end
  end

  describe '#get_account_key' do
    it 'raises NotExist before any key is stored' do
      expect { storage.get_account_key }.to raise_error(Acmesmith::Storages::Base::NotExist)
    end
  end

  describe '#put_account_key' do
    it 'succeeds on first call' do
      key = Acmesmith::AccountKey.generate
      expect { storage.put_account_key(key) }.not_to raise_error
    end

    it 'raises AlreadyExist on second call' do
      key = Acmesmith::AccountKey.generate
      storage.put_account_key(key)
      expect { storage.put_account_key(key) }.to raise_error(Acmesmith::Storages::Base::AlreadyExist)
    end

    it 'stores a key that can be retrieved with get_account_key' do
      key = Acmesmith::AccountKey.generate
      storage.put_account_key(key)
      retrieved = storage.get_account_key
      expect(retrieved).to be_a(Acmesmith::AccountKey)
      expect(retrieved.private_key.to_pem).to eq(key.private_key.to_pem)
    end
  end

  describe 'certificate operations' do
    let(:cert_name) { 'test.example.com' }
    let(:certificate) { build_test_certificate(name: cert_name) }
    let(:cert_version) { certificate.version }

    before do
      storage.put_certificate(certificate, nil, update_current: true)
    end

    describe '#put_certificate' do
      it 'stores a certificate successfully' do
        versions = storage.list_certificate_versions(cert_name)
        expect(versions).to contain_exactly(cert_version)
      end
    end

    describe '#get_certificate' do
      it 'returns the certificate by explicit version' do
        retrieved = storage.get_certificate(cert_name, version: cert_version)
        expect(retrieved).to be_a(Acmesmith::Certificate)
        expect(retrieved.certificate.to_pem).to eq(certificate.certificate.to_pem)
      end

      it "returns the certificate when version is 'current'" do
        retrieved = storage.get_certificate(cert_name, version: 'current')
        expect(retrieved).to be_a(Acmesmith::Certificate)
        expect(retrieved.certificate.to_pem).to eq(certificate.certificate.to_pem)
      end
    end

    describe '#list_certificates' do
      it 'returns the correct certificate names' do
        names = storage.list_certificates
        expect(names).to contain_exactly(cert_name)
      end

      context 'with multiple versions' do
        before do
          storage.put_certificate(build_test_certificate(name: cert_name), nil, update_current: true)
        end

        it 'returns the correct certificate names' do
          names = storage.list_certificates
          expect(names).to contain_exactly(cert_name)
        end
      end
    end

    describe '#list_certificate_versions' do
      it 'returns the correct version strings' do
        versions = storage.list_certificate_versions(cert_name)
        expect(versions).to contain_exactly(cert_version)
      end

      context 'with multiple versions' do
        let(:second_cert) { build_test_certificate(name: cert_name) }

        before do
          storage.put_certificate(second_cert, nil, update_current: true)
        end

        it 'returns all version strings' do
          versions = storage.list_certificate_versions(cert_name)
          expect(versions).to contain_exactly(cert_version, second_cert.version)
        end
      end
    end

    describe '#get_current_certificate_version' do
      it 'returns the current version' do
        version = storage.get_current_certificate_version(cert_name)
        expect(version).to eq(cert_version)
      end
    end
  end
end
