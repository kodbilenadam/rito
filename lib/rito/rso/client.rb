# frozen_string_literal: true

module Rito
  module RSO
    class Client
      attr_reader :provider, :client_id, :redirect_uri, :scope,
                  :open_timeout, :timeout, :adapter

      def initialize(provider: nil, client_id: nil, client_secret: nil, client_assertion: nil,
                     private_key: nil, redirect_uri: nil, scope: nil,
                     open_timeout: nil, timeout: nil, adapter: nil)
        @provider = (provider || RSO.provider).delete_suffix('/')
        @client_id = client_id || RSO.client_id
        @redirect_uri = redirect_uri || RSO.redirect_uri
        @scope = scope || RSO.scope || 'openid'
        @credential = Credential.new(
          client_secret: client_secret || RSO.client_secret,
          client_assertion: client_assertion || RSO.client_assertion,
          private_key: private_key || RSO.private_key
        )
        @open_timeout = open_timeout || Rito.open_timeout
        @timeout = timeout || Rito.timeout
        @adapter = adapter || Rito.adapter
        @jwks_mutex = Mutex.new
        @jwks = nil

        validate!
      end

      def authorization_url(scope: @scope, state: nil, login_hint: nil, ui_locales: nil)
        ensure_redirect_uri!
        state ||= SecureRandom.hex(32)
        params = {
          'client_id' => @client_id,
          'redirect_uri' => @redirect_uri,
          'response_type' => 'code',
          'scope' => scope,
          'state' => state
        }
        params['login_hint'] = login_hint if login_hint
        params['ui_locales'] = ui_locales if ui_locales
        AuthorizationRequest.new(url: "#{@provider}/authorize?#{URI.encode_www_form(params)}", state: state)
      end

      def exchange_code(code)
        request_token(grant_type: 'authorization_code', code: code, redirect_uri: @redirect_uri)
      end

      def refresh(refresh_token, scope: nil)
        params = { grant_type: 'refresh_token', refresh_token: refresh_token }
        params[:scope] = scope if scope
        request_token(**params)
      end

      def userinfo(access_token)
        response = http do
          connection.get('/userinfo') do |req|
            req.headers['Authorization'] = "Bearer #{access_token}"
          end
        end
        raise_rso_error!(response, 'GET', '/userinfo') unless response.status == 200
        Userinfo.from_api(response.body)
      end

      def jwks(force: false)
        @jwks_mutex.synchronize do
          @jwks = nil if force
          @jwks ||= fetch_jwks
        end
      end

      def verify_id_token(id_token, leeway: 60)
        header = Jwt.header(id_token)
        claims = Jwt.claims(id_token)
        verify_signature!(id_token, header)
        validate_claims!(claims, leeway)
        claims
      end

      private

      def request_token(params)
        params = @credential.token_params(params, client_id: @client_id, aud: @provider)
        response = http do
          connection.post('/token') do |req|
            req.headers['Authorization'] = @credential.authorization_header(@client_id) if @credential.basic?
            req.body = params
          end
        end
        raise_rso_error!(response, 'POST', '/token') unless response.status == 200
        Tokens.from_api(response.body)
      end

      def fetch_jwks
        response = http { connection.get('/jwks.json') }
        raise_rso_error!(response, 'GET', '/jwks.json') unless response.status == 200
        response.body
      end

      def verify_signature!(id_token, header)
        raise InvalidToken, "unsupported alg: #{header['alg'].inspect}" unless header['alg'] == 'RS256'

        key = signing_key_for(header['kid'])
        segments = id_token.split('.')
        signature = Jwt.base64url_decode(segments[2].to_s)
        valid = key.verify(OpenSSL::Digest.new('SHA256'), signature, "#{segments[0]}.#{segments[1]}")
        raise InvalidToken, 'invalid signature' unless valid
      end

      def signing_key_for(kid)
        key = key_from_jwks(jwks, kid)
        return key if key

        # Keypairs can be rotated without disabling the old one, so a miss on
        # a cached document triggers exactly one refresh.
        key_from_jwks(jwks(force: true), kid) || raise(InvalidToken, "unknown kid: #{kid.inspect}")
      end

      def key_from_jwks(document, kid)
        keys = document.is_a?(Hash) ? (document['keys'] || []) : []
        jwk = keys.find { |key| key['kid'] == kid && key['kty'] == 'RSA' }
        jwk && Jwks.public_key(jwk)
      end

      def validate_claims!(claims, leeway)
        exp = claims['exp']
        raise InvalidToken, 'missing exp claim' unless exp
        raise InvalidToken, 'token expired' if exp + leeway < Time.now.to_i

        raise InvalidToken, "unexpected issuer: #{claims['iss'].inspect}" unless claims['iss'] == @provider

        aud = claims['aud']
        audiences = aud.is_a?(Array) ? aud : [aud].compact
        return if audiences.include?(@client_id)

        raise InvalidToken, 'audience does not match client_id'
      end

      def raise_rso_error!(response, method, path)
        body = parse_error_body(response.body)
        detail = [body['error'], body['error_description']].compact.join(': ')
        base = "#{response.status} #{method} #{@provider}#{path}"
        raise OAuthError.new(
          detail.empty? ? base : "#{base}: #{detail}",
          error_code: body['error'],
          error_description: body['error_description'],
          response: response
        )
      end

      def parse_error_body(body)
        body = JSON.parse(body) if body.is_a?(String)
        body.is_a?(Hash) ? body : {}
      rescue JSON::ParserError
        {}
      end

      def http
        yield
      rescue Faraday::ConnectionFailed => e
        raise Rito::ConnectionError.new("#{e.class}: #{e.message}", wrapped: e)
      rescue Faraday::TimeoutError, Timeout::Error => e
        raise Rito::TimeoutError.new("#{e.class}: #{e.message}", wrapped: e)
      rescue Faraday::SSLError => e
        raise Rito::SSLError.new("#{e.class}: #{e.message}", wrapped: e)
      end

      def connection
        @connection ||= Faraday.new(@provider) do |f|
          f.options.open_timeout = @open_timeout
          f.options.timeout = @timeout
          f.request :url_encoded
          f.response :json, content_type: /\bjson$/
          f.adapter @adapter
        end
      end

      def ensure_redirect_uri!
        raise ConfigError, 'redirect_uri is required' if @redirect_uri.to_s.empty?
      end

      def validate!
        raise ConfigError, 'client_id is required' if @client_id.to_s.empty?
      end
    end
  end
end
