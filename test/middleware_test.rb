require "minitest/autorun"
require "rack/mock"
require "openssl"
require "staging_gate"

class StagingGateMiddlewareTest < Minitest::Test
  APP = ->(_env) { [ 200, { "content-type" => "text/plain" }, [ "app" ] ] }
  SECRET = "s3cret-key-base"

  def gate(password: "sekret", **options)
    StagingGate::Middleware.new(APP, password: password, secret: SECRET, **options)
  end

  def get(path = "/", password: "sekret", **env)
    gate(password: password).call(Rack::MockRequest.env_for(path, env))
  end

  def post_password(submitted, return_to: nil, password: "sekret")
    params = { "password" => submitted }
    params["return_to"] = return_to if return_to
    gate(password: password).call(Rack::MockRequest.env_for("/staging-gate", method: "POST", params: params))
  end

  def valid_cookie(password = "sekret")
    OpenSSL::HMAC.hexdigest("SHA256", SECRET, password)
  end

  def test_anonymous_requests_get_the_form_not_the_app
    status, _headers, body = get
    assert_equal 401, status
    assert_match(/Staging environment/, body.join)
    refute_match(/\Aapp\z/, body.join)
  end

  def test_open_paths_stay_reachable
    status, _headers, body = get("/up")
    assert_equal 200, status
    assert_equal "app", body.join
  end

  def test_the_right_password_sets_the_cookie_and_redirects_back
    status, headers, _body = post_password("sekret", return_to: "/admin")
    assert_equal 302, status
    assert_equal "/admin", headers["location"]
    assert_match(/staging_gate=#{valid_cookie}/, headers["set-cookie"])
    assert_match(/httponly/i, headers["set-cookie"])
  end

  def test_external_return_to_targets_are_ignored
    _status, headers, _body = post_password("sekret", return_to: "//evil.example")
    assert_equal "/", headers["location"]
  end

  def test_a_wrong_password_re_renders_the_form_with_an_error
    status, _headers, body = post_password("nope")
    assert_equal 401, status
    assert_match(/did not match/, body.join)
  end

  def test_the_cookie_grants_access
    status, _headers, body = get("HTTP_COOKIE" => "staging_gate=#{valid_cookie}")
    assert_equal 200, status
    assert_equal "app", body.join
  end

  def test_a_stale_cookie_from_a_rotated_password_is_rejected
    status, = get("HTTP_COOKIE" => "staging_gate=#{valid_cookie('old-password')}")
    assert_equal 401, status
  end

  def test_fail_closed_without_a_password
    status, = get(password: nil)
    assert_equal 401, status

    status, = post_password("", password: nil)
    assert_equal 401, status

    status, = get(password: "")
    assert_equal 401, status
  end

  def test_password_and_secret_may_be_callables_resolved_per_request
    current = "first"
    middleware = StagingGate::Middleware.new(APP, password: -> { current }, secret: -> { SECRET })
    _status, headers, = middleware.call(
      Rack::MockRequest.env_for("/staging-gate", method: "POST", params: { "password" => "first" })
    )
    cookie = headers["set-cookie"][/staging_gate=(\h+)/, 1]

    status, = middleware.call(Rack::MockRequest.env_for("/", "HTTP_COOKIE" => "staging_gate=#{cookie}"))
    assert_equal 200, status

    current = "second" # rotation: the old cookie dies at once
    status, = middleware.call(Rack::MockRequest.env_for("/", "HTTP_COOKIE" => "staging_gate=#{cookie}"))
    assert_equal 401, status
  end

  def test_options_customise_paths_cookie_and_title
    middleware = gate(cookie_name: "gate", form_path: "/knock", open_paths: [ "/health" ], title: "Preview")
    status, _headers, body = middleware.call(Rack::MockRequest.env_for("/"))
    assert_equal 401, status
    assert_match(/Preview/, body.join)
    assert_match(%r{action="/knock"}, body.join)

    status, = middleware.call(Rack::MockRequest.env_for("/health"))
    assert_equal 200, status

    _status, headers, = middleware.call(
      Rack::MockRequest.env_for("/knock", method: "POST", params: { "password" => "sekret" })
    )
    assert_match(/\Agate=/, headers["set-cookie"])
  end
end
