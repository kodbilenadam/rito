# frozen_string_literal: true

require_relative 'test_helper'

class RsoClientTest < Minitest::Test
  RSA_KEY = OpenSSL::PKey::RSA.generate(2048)
  PROVIDER = 'https://auth.riotgames.com'
  TOKEN_URL = "#{PROVIDER}/token".freeze
  USERINFO_URL = "#{PROVIDER}/userinfo".freeze
  JWKS_URL = "#{PROVIDER}/jwks.json".freeze
  REDIRECT_URI = 'https://app.example.com/oauth2-callback'

  def setup
    @token_response = {
      'scope' => 'openid',
      'expires_in' => 600,
      'token_type' => 'Bearer',
      'refresh_token' => 'refresh-jwt',
      'id_token' => 'id-jwt',
      'sub_sid' => 'sid-value',
      'access_token' => 'access-jwt'
    }
  end

  def with_rso_config(**options)
    keys = %i[provider client_id client_secret client_assertion private_key redirect_uri scope]
    originals = keys.to_h { |key| [key, Rito::RSO.public_send(key)] }
    options.each { |key, value| Rito::RSO.public_send("#{key}=", value) }
    yield
  ensure
    originals.each { |key, value| Rito::RSO.public_send("#{key}=", value) }
  end

  def client(**overrides)
    Rito::RSO::Client.new(
      client_id: 'client-123',
      client_secret: 'shhh',
      redirect_uri: REDIRECT_URI,
      **overrides
    )
  end

  def assert_query(url, expected)
    query = URI.decode_www_form(URI.parse(url).query).to_h
    expected.each { |key, value| assert_equal value, query[key], "query param #{key}" }
  end

  class AuthorizationUrlTest < RsoClientTest
    def test_includes_mandatory_params_and_generated_state
      request = client.authorization_url
      uri = URI.parse(request.url)

      assert_equal "#{PROVIDER}/authorize", "#{uri.scheme}://#{uri.host}#{uri.path}"
      assert_query(request.url, 'client_id' => 'client-123', 'redirect_uri' => REDIRECT_URI,
                                'response_type' => 'code', 'scope' => 'openid', 'state' => request.state)
      assert_match(/\A[0-9a-f]{64}\z/, request.state)
    end

    def test_explicit_state_is_echoed_back
      request = client.authorization_url(state: 'csrf-secret')

      assert_equal 'csrf-secret', request.state
      assert_query(request.url, 'state' => 'csrf-secret')
    end

    def test_optional_params
      request = client.authorization_url(login_hint: 'na1|daguava', ui_locales: 'en-US de-DE')

      assert_query(request.url, 'login_hint' => 'na1|daguava', 'ui_locales' => 'en-US de-DE')
    end

    def test_scope_override
      request = client.authorization_url(scope: 'openid cpid offline_access')

      assert_query(request.url, 'scope' => 'openid cpid offline_access')
    end

    def test_requires_redirect_uri
      error = assert_raises(Rito::ConfigError) do
        client(redirect_uri: nil).authorization_url
      end

      assert_match(/redirect_uri/, error.message)
    end
  end

  class ExchangeCodeTest < RsoClientTest
    def test_exchanges_code_with_client_secret_basic
      stub = stub_request(:post, TOKEN_URL)
             .with(
               headers: { 'Authorization' => "Basic #{['client-123:shhh'].pack('m0')}" },
               body: {
                 'grant_type' => 'authorization_code',
                 'code' => 'CxhkPgX8GiMKR4-E-YD8Ng',
                 'redirect_uri' => REDIRECT_URI
               }
             )
             .to_return(body: JSON.generate(@token_response),
                        headers: { 'Content-Type' => 'application/json' })

      tokens = client.exchange_code('CxhkPgX8GiMKR4-E-YD8Ng')

      assert_requested stub
      assert_equal 'access-jwt', tokens.access_token
      assert_equal 'id-jwt', tokens.id_token
      assert_equal 'refresh-jwt', tokens.refresh_token
      assert_equal 'Bearer', tokens.token_type
      assert_equal 'openid', tokens.scope
      assert_equal 600, tokens.expires_in
      assert_equal 'sid-value', tokens.sub_sid
      assert_equal 'sid-value', tokens.raw['sub_sid']
    end

    def test_sends_static_client_assertion
      stub = stub_request(:post, TOKEN_URL)
             .with { |req| assert_client_assertion_form(req, 'static-assertion') && req.headers['Authorization'].nil? }
             .to_return(body: JSON.generate(@token_response), headers: { 'Content-Type' => 'application/json' })

      client(client_secret: nil, client_assertion: 'static-assertion').exchange_code('abc')

      assert_requested stub
    end

    def test_rotated_refresh_token_on_refresh
      refreshed = @token_response.merge('refresh_token' => 'new-refresh-jwt')
      stub = stub_request(:post, TOKEN_URL)
             .with(body: { 'grant_type' => 'refresh_token', 'refresh_token' => 'refresh-jwt' })
             .to_return(body: JSON.generate(refreshed), headers: { 'Content-Type' => 'application/json' })

      tokens = client.refresh('refresh-jwt')

      assert_requested stub
      assert_equal 'new-refresh-jwt', tokens.refresh_token
    end

    def test_refresh_with_scope_narrowing
      stub = stub_request(:post, TOKEN_URL)
             .with(body: { 'grant_type' => 'refresh_token', 'refresh_token' => 'refresh-jwt', 'scope' => 'openid' })
             .to_return(body: JSON.generate(@token_response), headers: { 'Content-Type' => 'application/json' })

      client.refresh('refresh-jwt', scope: 'openid')

      assert_requested stub
    end

    def test_invalid_grant_raises_oauth_error
      stub_request(:post, TOKEN_URL)
        .to_return(status: 400,
                   body: JSON.generate('error' => 'invalid_grant', 'error_description' => 'code already used'),
                   headers: { 'Content-Type' => 'application/json' })

      error = assert_raises(Rito::RSO::OAuthError) do
        client.exchange_code('used-code')
      end

      assert_equal 400, error.status
      assert_equal 'invalid_grant', error.error_code
      assert_equal 'code already used', error.error_description
      assert_match(/invalid_grant: code already used/, error.message)
    end

    def test_requires_credentials
      error = assert_raises(Rito::ConfigError) do
        client(client_secret: nil).exchange_code('abc')
      end

      assert_match(/client_secret, client_assertion, or private_key/, error.message)
    end

    def test_rejects_multiple_credentials
      error = assert_raises(Rito::ConfigError) do
        client(client_assertion: 'also-this')
      end

      assert_match(/only one/, error.message)
    end

    private

    def assert_client_assertion_form(request, assertion)
      form = URI.decode_www_form(request.body).to_h
      form['client_assertion_type'] == Rito::RSO::JWT_BEARER_TYPE && form['client_assertion'] == assertion
    end
  end

  class PrivateKeyJwtTest < RsoClientTest
    def test_minted_assertion_is_signed_and_wellformed
      captured = nil
      stub_request(:post, TOKEN_URL)
        .with do |req|
        captured = req.body
        true
      end
        .to_return(body: JSON.generate(@token_response), headers: { 'Content-Type' => 'application/json' })

      client(client_secret: nil, private_key: RSA_KEY).exchange_code('abc')

      form = URI.decode_www_form(captured).to_h
      assert_equal Rito::RSO::JWT_BEARER_TYPE, form['client_assertion_type']

      assertion = form['client_assertion']
      header = Rito::RSO::Jwt.header(assertion)
      claims = Rito::RSO::Jwt.claims(assertion)
      assert_equal 'RS256', header['alg']

      signing_input = assertion.split('.').first(2).join('.')
      signature = Rito::RSO::Jwt.base64url_decode(assertion.split('.')[2])
      assert RSA_KEY.public_key.verify(OpenSSL::Digest.new('SHA256'), signature, signing_input)

      assert_equal 'client-123', claims['iss']
      assert_equal 'client-123', claims['sub']
      assert_equal PROVIDER, claims['aud']
      assert claims['exp'] > Time.now.to_i
      assert claims['jti']
    end

    def test_rejects_non_rsa_key
      error = assert_raises(Rito::ConfigError) do
        client(client_secret: nil, private_key: 'not-a-key')
      end

      assert_match(/not a valid RSA key/, error.message)
    end
  end

  class UserinfoTest < RsoClientTest
    def test_returns_userinfo
      stub = stub_request(:get, USERINFO_URL)
             .with(headers: { 'Authorization' => 'Bearer access-jwt' })
             .to_return(body: JSON.generate('sub' => 'sub-abc', 'cpid' => 'NA1'),
                        headers: { 'Content-Type' => 'application/json' })

      userinfo = client.userinfo('access-jwt')

      assert_requested stub
      assert_equal 'sub-abc', userinfo.sub
      assert_equal 'NA1', userinfo.cpid
    end

    def test_unauthorized_raises_oauth_error
      stub_request(:get, USERINFO_URL)
        .to_return(status: 401, body: JSON.generate('error' => 'invalid_token'),
                   headers: { 'Content-Type' => 'application/json' })

      error = assert_raises(Rito::RSO::OAuthError) do
        client.userinfo('expired')
      end

      assert_equal 401, error.status
      assert_equal 'invalid_token', error.error_code
    end
  end

  class JwksTest < RsoClientTest
    def jwk_for(key, kid: 'sig-key')
      n = Rito::RSO::Jwt.base64url_encode(key.public_key.n.to_s(2))
      e = Rito::RSO::Jwt.base64url_encode(key.public_key.e.to_s(2))
      { 'kty' => 'RSA', 'use' => 'sig', 'kid' => kid, 'alg' => 'RS256', 'n' => n, 'e' => e }
    end

    def signed_id_token(claims, key: RSA_KEY, kid: 'sig-key')
      Rito::RSO::Jwt.sign_rs256(claims, key, header_claims: { 'alg' => 'RS256', 'kid' => kid, 'typ' => 'JWT' })
    end

    def base_claims
      {
        'iss' => PROVIDER,
        'aud' => 'client-123',
        'sub' => 'sub-abc',
        'iat' => Time.now.to_i - 10,
        'exp' => Time.now.to_i + 600
      }
    end

    def stub_jwks(document)
      stub_request(:get, JWKS_URL)
        .to_return(body: JSON.generate(document), headers: { 'Content-Type' => 'application/json' })
    end

    def test_verifies_valid_id_token
      stub_jwks('keys' => [jwk_for(RSA_KEY)])
      token = signed_id_token(base_claims)

      claims = client.verify_id_token(token)

      assert_equal 'sub-abc', claims['sub']
    end

    def test_caches_jwks_document
      stub = stub_jwks('keys' => [jwk_for(RSA_KEY)])
      token = signed_id_token(base_claims)
      rso = client

      rso.verify_id_token(token)
      rso.verify_id_token(token)

      assert_requested stub, times: 1
    end

    def test_rejects_bad_signature
      stub_jwks('keys' => [jwk_for(RSA_KEY)])
      token = signed_id_token(base_claims)
      segments = token.split('.')
      tampered = "#{segments[0]}.#{segments[1]}x"

      error = assert_raises(Rito::RSO::InvalidToken) do
        client.verify_id_token(tampered)
      end

      assert_match(/invalid signature/, error.message)
    end

    def test_rejects_unknown_alg
      stub_jwks('keys' => [jwk_for(RSA_KEY)])

      header = { 'alg' => 'none', 'kid' => 'sig-key', 'typ' => 'JWT' }
      forged = [Rito::RSO::Jwt.base64url_encode(JSON.generate(header)),
                Rito::RSO::Jwt.base64url_encode(JSON.generate(base_claims)), ''].join('.')

      error = assert_raises(Rito::RSO::InvalidToken) do
        client.verify_id_token(forged)
      end

      assert_match(/unsupported alg/, error.message)
    end

    def test_rejects_expired_token
      stub_jwks('keys' => [jwk_for(RSA_KEY)])
      token = signed_id_token(base_claims.merge('exp' => Time.now.to_i - 100))

      error = assert_raises(Rito::RSO::InvalidToken) do
        client.verify_id_token(token)
      end

      assert_match(/expired/, error.message)
    end

    def test_rejects_wrong_issuer
      stub_jwks('keys' => [jwk_for(RSA_KEY)])
      token = signed_id_token(base_claims.merge('iss' => 'https://evil.example.com'))

      error = assert_raises(Rito::RSO::InvalidToken) do
        client.verify_id_token(token)
      end

      assert_match(/unexpected issuer/, error.message)
    end

    def test_rejects_wrong_audience
      stub_jwks('keys' => [jwk_for(RSA_KEY)])
      token = signed_id_token(base_claims.merge('aud' => 'other-client'))

      error = assert_raises(Rito::RSO::InvalidToken) do
        client.verify_id_token(token)
      end

      assert_match(/audience/, error.message)
    end

    def test_refetches_jwks_on_unknown_kid
      stub_jwks('keys' => [jwk_for(RSA_KEY, kid: 'old-key')])
        .to_return(body: JSON.generate('keys' => [jwk_for(RSA_KEY, kid: 'rotated-key')]),
                   headers: { 'Content-Type' => 'application/json' })
      token = signed_id_token(base_claims, kid: 'rotated-key')

      claims = client.verify_id_token(token)

      assert_equal 'sub-abc', claims['sub']
    end

    def test_fails_after_refetch_misses_kid
      stub_jwks('keys' => [jwk_for(RSA_KEY, kid: 'old-key')])
      token = signed_id_token(base_claims, kid: 'other-key')

      error = assert_raises(Rito::RSO::InvalidToken) do
        client.verify_id_token(token)
      end

      assert_match(/unknown kid/, error.message)
    end

    def test_tokens_model_decodes_jwt_claims
      token = signed_id_token(base_claims)
      tokens = Rito::RSO::Tokens.from_api(@token_response.merge('id_token' => token, 'refresh_token' => token))

      assert_equal 'sub-abc', tokens.id_token_claims['sub']
      assert_equal 'sub-abc', tokens.refresh_token_claims['sub']
    end
  end

  class ModuleConfigTest < RsoClientTest
    def test_reads_defaults_from_module_config
      with_rso_config(client_id: 'mod-id', client_secret: 'mod-secret', redirect_uri: REDIRECT_URI) do
        rso = Rito::RSO::Client.new

        assert_equal 'mod-id', rso.client_id
        assert_equal REDIRECT_URI, rso.redirect_uri
      end
    end

    def test_instance_overrides_module_config
      with_rso_config(client_id: 'mod-id', client_secret: 'mod-secret', redirect_uri: REDIRECT_URI) do
        rso = Rito::RSO::Client.new(client_id: 'other-id')

        assert_equal 'other-id', rso.client_id
      end
    end

    def test_requires_client_id
      with_rso_config(client_id: nil) do
        error = assert_raises(Rito::ConfigError) do
          Rito::RSO::Client.new(client_secret: 's')
        end

        assert_match(/client_id is required/, error.message)
      end
    end

    def test_default_scope_is_openid
      with_rso_config(client_id: 'id', client_secret: 's', scope: nil, redirect_uri: REDIRECT_URI) do
        request = Rito::RSO::Client.new.authorization_url

        assert_query(request.url, 'scope' => 'openid')
      end
    end
  end
end
