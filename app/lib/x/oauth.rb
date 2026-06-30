require "net/http"
require "uri"
require "json"
require "base64"
require "digest"
require "securerandom"

# OAuth 2.0 user-context flow for X (Twitter). Used by Fleet Social workspaces
# so each workspace can connect its own X account. This is separate from the
# legacy XClient (OAuth 1.0a, single @agent44bot account, env-var creds).
module X
  class Oauth
    AUTHORIZE_URL  = "https://twitter.com/i/oauth2/authorize"
    TOKEN_URL      = "https://api.x.com/2/oauth2/token"
    ME_URL         = "https://api.x.com/2/users/me"
    # media.write is required to upload images/video via /2/media/upload.
    # Accounts connected before this scope was added must reconnect once to
    # get a token that carries it (text-only posting keeps working meanwhile).
    DEFAULT_SCOPES = %w[tweet.read tweet.write media.write users.read offline.access].freeze

    TokenResult = Struct.new(:ok?, :access_token, :refresh_token, :expires_in, :scope, :token_type, :error, :status, keyword_init: true) do
      # A failure worth retrying later instead of forcing a reconnect: X 5xx,
      # rate limiting (429), or a network error (status nil). A 4xx is a real
      # auth problem (invalid_grant / invalid_client) -> the user must reconnect.
      def retryable?
        return false if ok?
        s = status.to_s
        s.empty? || s.start_with?("5") || s == "429"
      end
    end
    UserResult  = Struct.new(:ok?, :id, :username, :name, :error, keyword_init: true)

    class << self
      # Swap with a Proc(method, url, params|nil, headers) -> [status, body_hash] in tests.
      attr_accessor :http_stub

      def configured?
        client_id.present? && client_secret.present?
      end

      def client_id
        Rails.application.credentials.dig(:x, :oauth_client_id) || ENV["X_OAUTH_CLIENT_ID"]
      end

      def client_secret
        Rails.application.credentials.dig(:x, :oauth_client_secret) || ENV["X_OAUTH_CLIENT_SECRET"]
      end

      def generate_verifier
        SecureRandom.urlsafe_base64(64)
      end

      def challenge_for(verifier)
        Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
      end

      def authorization_url(redirect_uri:, state:, code_verifier:, scopes: DEFAULT_SCOPES)
        params = {
          response_type:         "code",
          client_id:             client_id,
          redirect_uri:          redirect_uri,
          scope:                 scopes.join(" "),
          state:                 state,
          code_challenge:        challenge_for(code_verifier),
          code_challenge_method: "S256"
        }
        "#{AUTHORIZE_URL}?#{URI.encode_www_form(params)}"
      end

      def exchange_code(code:, redirect_uri:, code_verifier:)
        status, body = post_form(TOKEN_URL, {
          code:          code,
          grant_type:    "authorization_code",
          client_id:     client_id,
          redirect_uri:  redirect_uri,
          code_verifier: code_verifier
        })
        parse_token_response(status, body)
      end

      def refresh(refresh_token:)
        status, body = post_form(TOKEN_URL, {
          grant_type:    "refresh_token",
          refresh_token: refresh_token,
          client_id:     client_id
        })
        parse_token_response(status, body)
      rescue => e
        # Network/timeout: treat as transient (status nil -> retryable?), so a
        # blip reaching X doesn't get mistaken for a revoked token.
        TokenResult.new(ok?: false, status: nil, error: "#{e.class}: #{e.message}")
      end

      def me(access_token:)
        status, body = get_json(ME_URL, headers: { "Authorization" => "Bearer #{access_token}" })
        if status == "200"
          data = body["data"] || {}
          UserResult.new(ok?: true, id: data["id"], username: data["username"], name: data["name"])
        else
          UserResult.new(ok?: false, error: format_error(status, body))
        end
      rescue => e
        UserResult.new(ok?: false, error: "#{e.class}: #{e.message}")
      end

      private

      def post_form(url, params)
        return http_stub.call(:post, url, params, nil) if http_stub
        uri = URI(url)
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/x-www-form-urlencoded"
        req.basic_auth(client_id, client_secret)
        req.body = URI.encode_www_form(params)
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
        [ res.code, parse_json(res.body) ]
      end

      def get_json(url, headers: {})
        return http_stub.call(:get, url, nil, headers) if http_stub
        uri = URI(url)
        req = Net::HTTP::Get.new(uri)
        headers.each { |k, v| req[k] = v }
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
        [ res.code, parse_json(res.body) ]
      end

      def parse_json(body)
        JSON.parse(body.to_s)
      rescue JSON::ParserError
        {}
      end

      def parse_token_response(status, body)
        body ||= {}
        if status == "200" && body["access_token"].present?
          TokenResult.new(ok?: true,
            access_token:  body["access_token"],
            refresh_token: body["refresh_token"],
            expires_in:    body["expires_in"],
            scope:         body["scope"],
            token_type:    body["token_type"],
            status:        status
          )
        else
          TokenResult.new(ok?: false, status: status, error: format_error(status, body))
        end
      end

      def format_error(status, body)
        msg = body["error_description"] || body["detail"] || body["error"] || body["title"]
        "HTTP #{status}#{msg ? ": #{msg}" : ""}"
      end
    end
  end
end
