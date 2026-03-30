require_relative "lib/acmesmith/kubernetes/version"

Gem::Specification.new do |spec|
  spec.name = "acmesmith-kubernetes"
  spec.version = Acmesmith::Kubernetes::VERSION
  spec.authors = ["Kasumi Hanazuki"]
  spec.email = ["kasumi@rollingapple.net"]

  spec.summary = "Kubernetes integration for Acmesmith"
  spec.description = "Acmesmith plugin for Kubernetes: store Acmesmith state in Kubernetes Secrets and export certificates as TLS secrets"
  spec.homepage = "https://github.com/hanazuki/acmesmith-kubernetes"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "acmesmith", "~> 2.0"
  spec.add_dependency "kubeclient", "~> 4.0"
end
