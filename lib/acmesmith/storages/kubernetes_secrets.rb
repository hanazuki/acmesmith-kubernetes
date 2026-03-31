require 'acmesmith/storages/base'
require 'acmesmith/account_key'
require 'acmesmith/certificate'
require 'acmesmith/kubernetes'
require 'kubeclient'
require 'base64'
require 'digest'
require 'securerandom'

module Acmesmith
  module Storages
    class KubernetesSecrets < Base
      include Acmesmith::Kubernetes

      LABEL_INSTANCE = 'acmesmith-kubernetes.hanazuki.dev/instance'
      LABEL_CERT_NAME = 'acmesmith-kubernetes.hanazuki.dev/certificate.name.hash'
      LABEL_CERT_VERSION = 'acmesmith-kubernetes.hanazuki.dev/certificate.version'
      ANNOT_CERT_NAME = 'acmesmith-kubernetes.hanazuki.dev/certificate.name'

      TYPE_ACCOUNT = 'acmesmith-kubernetes.hanazuki.dev/account'
      TYPE_CERTIFICATE = 'acmesmith-kubernetes.hanazuki.dev/certificate'
      TYPE_CURRENT = 'acmesmith-kubernetes.hanazuki.dev/current-certificate'

      def initialize(instance:, namespace: 'default', name_prefix: 'acmesmith-')
        @instance = instance
        @namespace = namespace
        @name_prefix = name_prefix
      end

      def get_account_key
        secrets = list_secrets_by(type: TYPE_ACCOUNT, labels: instance_labels)
        raise NotExist, 'No account key found' if secrets.empty?
        pem = Base64.strict_decode64(secrets.first.data['account.pem'])
        Acmesmith::AccountKey.new(pem)
      end

      def put_account_key(key, passphrase = nil)
        existing = list_secrets_by(type: TYPE_ACCOUNT, labels: instance_labels)
        raise AlreadyExist, 'Account key already exists' unless existing.empty?

        secret = Kubeclient::Resource.new(
          metadata: {
            name: "#{@name_prefix}account-#{random_suffix}",
            namespace: @namespace,
            labels: instance_labels,
          },
          type: TYPE_ACCOUNT,
          data: {
            'account.pem' => Base64.strict_encode64(key.export(passphrase)),
          },
        )
        kubernetes_client.create_secret(secret)
      end

      def put_certificate(cert, passphrase = nil, update_current: true)
        exported = cert.export(passphrase)

        cert_secret = Kubeclient::Resource.new(
          metadata: {
            name: "#{@name_prefix}certificate-#{random_suffix}",
            namespace: @namespace,
            labels: instance_labels.merge(
              LABEL_CERT_NAME => name_hash(cert.name),
              LABEL_CERT_VERSION => cert.version,
            ),
            annotations: {
              ANNOT_CERT_NAME => cert.name,
            },
          },
          type: TYPE_CERTIFICATE,
          data: {
            'cert.pem' => Base64.strict_encode64(exported.certificate),
            'key.pem' => Base64.strict_encode64(exported.private_key),
            'chain.pem' => Base64.strict_encode64(exported.chain),
            'fullchain.pem' => Base64.strict_encode64(exported.fullchain),
          },
        )
        kubernetes_client.create_secret(cert_secret)

        if update_current
          current_labels = instance_labels.merge(LABEL_CERT_NAME => name_hash(cert.name))
          current_secrets = list_secrets_by(type: TYPE_CURRENT, labels: current_labels)

          if !current_secrets.empty?
            kubernetes_client.patch_secret(
              current_secrets.first.metadata.name,
              { data: { 'version' => Base64.strict_encode64(cert.version) } },
              @namespace,
            )
          else
            current_secret = Kubeclient::Resource.new(
              metadata: {
                name: "#{@name_prefix}current-certificate-#{random_suffix}",
                namespace: @namespace,
                labels: current_labels,
                annotations: {
                  ANNOT_CERT_NAME => cert.name,
                },
              },
              type: TYPE_CURRENT,
              data: {
                'version' => Base64.strict_encode64(cert.version),
              },
            )
            kubernetes_client.create_secret(current_secret)
          end
        end
      end

      def get_certificate(name, version: 'current')
        version = get_current_certificate_version(name) if version == 'current'

        secrets = list_secrets_by(
          type: TYPE_CERTIFICATE,
          labels: instance_labels.merge(
            LABEL_CERT_NAME => name_hash(name),
            LABEL_CERT_VERSION => version,
          ),
        )
        raise NotExist, "Certificate #{name} version #{version} not found" if secrets.empty?

        data = secrets.first.data
        Acmesmith::Certificate.new(
          Base64.strict_decode64(data['cert.pem']),
          Base64.strict_decode64(data['chain.pem']),
          Base64.strict_decode64(data['key.pem']),
        )
      end

      def list_certificates
        list_secrets_by(type: TYPE_CURRENT, labels: instance_labels).map do |s|
          s.metadata.annotations[ANNOT_CERT_NAME]
        end
      end

      def list_certificate_versions(name)
        list_secrets_by(
          type: TYPE_CERTIFICATE,
          labels: instance_labels.merge(LABEL_CERT_NAME => name_hash(name)),
        ).map { it.metadata.labels[LABEL_CERT_VERSION] }
      end

      def get_current_certificate_version(name)
        secrets = list_secrets_by(
          type: TYPE_CURRENT,
          labels: instance_labels.merge(LABEL_CERT_NAME => name_hash(name)),
        )
        raise NotExist, "No current certificate for #{name}" if secrets.empty?
        Base64.strict_decode64(secrets.first.data['version'])
      end

      private

      def kubernetes_client
        @kubernetes_client ||= build_kubernetes_client
      end

      def name_hash(name)
        Digest::SHA256.hexdigest(name)[0, 56]
      end

      def random_suffix
        SecureRandom.hex(4)
      end

      def instance_labels
        { LABEL_INSTANCE => @instance }
      end

      def list_secrets_by(type:, labels:)
        label_selector = labels.map {|k, v| "#{k}=#{v}" }.join(',')
        kubernetes_client.get_secrets(
          namespace: @namespace,
          label_selector: label_selector,
          field_selector: "type=#{type}",
        ).to_a
      end
    end
  end
end
