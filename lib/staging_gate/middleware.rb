require "openssl"
require "rack"

module StagingGate
  # Shared-password gate in front of the whole app: visitors see a minimal
  # password form; the right password sets a cookie and lets them use the app
  # normally. Fail-closed — if no password is configured, nobody gets in.
  #
  # The cookie carries an HMAC of the password keyed by `secret`, so rotating
  # the password invalidates every cookie already handed out.
  #
  #   use StagingGate::Middleware, password: ENV["STAGING_GATE_PASSWORD"],
  #                                secret: ENV["SECRET_KEY_BASE"]
  #
  # `password` and `secret` may be callables — resolved per request, so a
  # value read from credentials at boot or rotated at runtime both work.
  class Middleware
    DEFAULTS = {
      cookie_name: "staging_gate",
      form_path: "/staging-gate",
      open_paths: [ "/up" ], # health check stays reachable
      title: "Staging environment"
    }.freeze

    def initialize(app, password:, secret:, **options)
      @app = app
      @password = password
      @secret = secret
      @options = DEFAULTS.merge(options)
    end

    def call(env)
      request = Rack::Request.new(env)

      return @app.call(env) if open_paths.include?(request.path)
      return @app.call(env) if authorized?(request)
      return attempt(request) if request.post? && request.path == form_path

      challenge(request)
    end

    private

    def password = resolve(@password)
    def secret = resolve(@secret)
    def cookie_name = @options[:cookie_name]
    def form_path = @options[:form_path]
    def open_paths = @options[:open_paths]

    def resolve(value)
      value = value.call if value.respond_to?(:call)
      value = value.to_s
      value.empty? ? nil : value
    end

    def token
      OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, password.to_s)
    end

    def authorized?(request)
      return false if password.nil? || secret.nil?

      cookie = request.cookies[cookie_name].to_s
      !cookie.empty? && Rack::Utils.secure_compare(cookie, token)
    end

    def attempt(request)
      submitted = request.params["password"].to_s
      if password && secret && !submitted.empty? && Rack::Utils.secure_compare(submitted, password)
        response = Rack::Response.new
        response.redirect(safe_return_path(request.params["return_to"]))
        response.set_cookie(cookie_name, value: token, path: "/", httponly: true,
                                         same_site: :lax, secure: request.ssl?)
        response.finish
      else
        challenge(request, error: true)
      end
    end

    # Only same-origin paths — never an absolute URL someone smuggled in.
    def safe_return_path(path)
      path = path.to_s
      path.start_with?("/") && !path.start_with?("//") ? path : "/"
    end

    def challenge(request, error: false)
      [ 401, { "content-type" => "text/html; charset=utf-8" }, [ form_html(request, error: error) ] ]
    end

    # Self-contained page: no dependency on an asset pipeline or the app.
    def form_html(request, error:)
      return_to = Rack::Utils.escape_html(request.fullpath)
      title = Rack::Utils.escape_html(@options[:title])
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <meta name="robots" content="noindex">
          <title>#{title} — restricted</title>
          <style>
            body { font-family: system-ui, sans-serif; display: grid; place-items: center;
                   min-height: 100dvh; margin: 0; background: oklch(98% 0.004 106); }
            form { display: grid; gap: 0.75rem; padding: 2rem; min-width: 18rem;
                   background: oklch(100% 0 none); border: 1px solid oklch(90% 0.01 258);
                   border-radius: 0.625rem; }
            h1 { font-size: 1.1rem; margin: 0; }
            input { padding: 0.55rem 0.7rem; border: 1px solid oklch(85% 0.01 258);
                    border-radius: 0.5rem; font: inherit; }
            button { padding: 0.55rem 0.7rem; border: 0; border-radius: 0.5rem; font: inherit;
                     font-weight: 700; background: oklch(35% 0.09 262); color: white; cursor: pointer; }
            .error { color: oklch(55% 0.17 29); font-size: 0.9rem; margin: 0; }
          </style>
        </head>
        <body>
          <form method="post" action="#{form_path}">
            <h1>#{title}</h1>
            #{error ? '<p class="error">That password did not match.</p>' : ""}
            <input type="hidden" name="return_to" value="#{return_to}">
            <input type="password" name="password" autofocus required autocomplete="current-password" aria-label="Access password">
            <button type="submit">Enter</button>
          </form>
        </body>
        </html>
      HTML
    end
  end
end
