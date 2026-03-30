require_relative '../spec_helper'

require 'openssl'
require 'securerandom'

def build_test_certificate(name: 'test.example.com')
  key = OpenSSL::PKey::EC.generate('prime256v1')
  cert = OpenSSL::X509::Certificate.new
  cert.version = 2
  cert.serial = OpenSSL::BN.rand(128)
  cert.subject = OpenSSL::X509::Name.parse("CN=#{name}")
  cert.issuer = cert.subject
  cert.public_key = key
  cert.not_before = Time.now
  cert.not_after = Time.now + 3600
  cert.sign(key, OpenSSL::Digest::SHA256.new)
  Acmesmith::Certificate.new(cert.to_pem, nil, key)
end
