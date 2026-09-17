require_relative "lib/staging_gate/version"

Gem::Specification.new do |spec|
  spec.name        = "staging_gate"
  spec.version     = StagingGate::VERSION
  spec.authors     = [ "Oleh Khomei" ]
  spec.summary     = "Shared-password gate in front of a whole Rack app — for staging environments."
  spec.description = <<~TEXT
    Rack middleware that puts one password in front of everything: visitors see a
    self-contained form, the right password sets an HMAC cookie and the app works
    normally. Fail-closed when no password is configured; rotating the password
    invalidates every cookie. Ships a Railtie that wires it into a Rails
    environment with one line.
  TEXT
  spec.homepage    = "https://github.com/varyform/staging_gate"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "rack", ">= 2.2"

  spec.add_development_dependency "minitest"
  spec.add_development_dependency "rack-test"
end
