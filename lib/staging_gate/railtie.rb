module StagingGate
  # One-line wiring for Rails: in the gated environment's config,
  #
  #   config.staging_gate.enabled = true
  #
  # The middleware is appended to the stack (after ActionDispatch::Static, so
  # fingerprinted assets and /up stay reachable; every dynamic route is gated).
  # Password: STAGING_GATE_PASSWORD, else credentials.staging_gate_password.
  # Cookie HMAC key: the app's secret_key_base. Both are read per request.
  # Any Middleware option can be set the same way (config.staging_gate.title…).
  class Railtie < Rails::Railtie
    config.staging_gate = ActiveSupport::OrderedOptions.new
    config.staging_gate.enabled = false

    initializer "staging_gate.middleware" do |app|
      next unless app.config.staging_gate.enabled

      options = app.config.staging_gate.to_h.except(:enabled, :password, :secret)
      password = app.config.staging_gate.password ||
                 -> { ENV["STAGING_GATE_PASSWORD"].presence || app.credentials.staging_gate_password.presence }
      secret = app.config.staging_gate.secret || -> { app.secret_key_base }

      app.middleware.use StagingGate::Middleware, password: password, secret: secret, **options
    end
  end
end
