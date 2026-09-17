# staging_gate

One shared password in front of a whole Rack app — for staging and preview
environments that should not be public but don't need real accounts.

- Visitors see a minimal, self-contained password form (no asset pipeline).
- The right password sets a cookie carrying an HMAC of the password, keyed by
  your secret — **rotating the password invalidates every cookie** at once.
- **Fail-closed:** no configured password means nobody gets in.
- Health check (`/up`) stays reachable; `return_to` only accepts same-origin paths.

## Rails

```ruby
# Gemfile
gem "staging_gate"

# config/environments/staging.rb
config.staging_gate.enabled = true
```

The middleware is appended to the stack (after `ActionDispatch::Static`, so
fingerprinted assets stay reachable). The password comes from
`STAGING_GATE_PASSWORD`, else `Rails.application.credentials.staging_gate_password`;
the cookie key is `secret_key_base`. Both are read per request.

Any option below can be set the same way, e.g. `config.staging_gate.title = "Preview"`.

## Plain Rack

```ruby
use StagingGate::Middleware, password: ENV["STAGING_GATE_PASSWORD"],
                             secret: ENV["SECRET_KEY_BASE"]
```

`password` and `secret` may be strings or callables (resolved on every request).

## Options

| Option | Default | |
|---|---|---|
| `cookie_name` | `"staging_gate"` | |
| `form_path` | `"/staging-gate"` | where the form posts |
| `open_paths` | `["/up"]` | exact paths that bypass the gate |
| `title` | `"Staging environment"` | form heading |

## Tests

```
cd gems/staging_gate && ruby -Ilib -Itest test/middleware_test.rb
```
