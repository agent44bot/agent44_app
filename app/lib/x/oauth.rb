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
    UserResult  = Struct.new(:ok?, :id, :username, :name, :error, :status, keyword_init: true) do
      # The profile read happens right after we mint a token during connect, so
      # a 401/5xx/429/network there is treated as a transient X hiccup and
      # retried (bounded). A genuinely bad token still settles out after the
      # retry budget. (Looser than TokenResult#retryable?, which excludes 401,
      # because here we already hold a freshly issued token.)
      def retryable?
        return false if ok?
        s = status.to_s
        s.empty? || s.start_with?("5") || s == "429" || s == "401"
      end
    end

    class << self
      # Swap with a Proc(method, url, params|nil, headers) -> [status, body_hash] in tests.
      attr_accessor :http_stub
      # Seconds of linear backoff between connect retries; tests set this to 0.
      attr_writer :retry_backoff
      def retry_backoff = @retry_backoff.nil? ? 1.0 : @retry_backoff

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

      # Connect runs inside the OAuth callback (a live request), and X's token
      # endpoint flaps with 503s. Retry a transient failure a couple times with
      # a short backoff so one blip doesn't make the user redo the whole
      # authorize flow. A 5xx means X didn't accept the (single-use) code, so
      # re-presenting it is safe; a 4xx (bad/expired code) returns immediately.
      def exchange_code(code:, redirect_uri:, code_verifier:)
        params = {
          code:          code,
          grant_type:    "authorization_code",
          client_id:     client_id,
          redirect_uri:  redirect_uri,
          code_verifier: code_verifier
        }
        with_token_retry { post_token_form(params) }
      end

      def refresh(refresh_token:)
        post_token_form(grant_type: "refresh_token", refresh_token: refresh_token, client_id: client_id)
      end

      # Read the connecting user's profile. X sometimes 401s/5xxs this call for
      # a moment right after issuing the token (seen during X outages), which
      # would otherwise fail the whole connect even though the token is good, so
      # retry transient failures (bounded) before giving up.
      def me(access_token:)
        with_token_retry { fetch_me(access_token) }
      end

      private

      # GET /2/users/me, never raising: a network error becomes a transient
      # result (status nil -> retryable?) so with_token_retry retries it.
      def fetch_me(access_token)
        status, body = get_json(ME_URL, headers: { "Authorization" => "Bearer #{access_token}" })
        if status == "200"
          data = body["data"] || {}
          UserResult.new(ok?: true, status: status, id: data["id"], username: data["username"], name: data["name"])
        else
          UserResult.new(ok?: false, status: status, error: format_error(status, body))
        end
      rescue => e
        UserResult.new(ok?: false, status: nil, error: "#{e.class}: #{e.message}")
      end

      # POST the token endpoint and parse, never raising: a network/timeout
      # error becomes a transient result (status nil -> retryable?), so callers
      # treat it like a 5xx rather than a revoked token.
      def post_token_form(params)
        status, body = post_form(TOKEN_URL, params)
        parse_token_response(status, body)
      rescue => e
        TokenResult.new(ok?: false, status: nil, error: "#{e.class}: #{e.message}")
      end

      # Retry a transient (retryable?) token result a few times with linear
      # backoff. Used by exchange_code so a flaky X 503 during the connect
      # callback auto-retries instead of dumping the user back to "not connected".
      def with_token_retry(max: 2)
        attempt = 0
        loop do
          result = yield
          return result if result.ok? || !result.retryable? || attempt >= max
          attempt += 1
          sleep(retry_backoff * attempt)
        end
      end

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
