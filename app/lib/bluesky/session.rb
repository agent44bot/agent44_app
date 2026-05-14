require "net/http"
require "uri"
require "json"

# AT Protocol session management for Bluesky. Unlike X, Bluesky has no
# OAuth dance — users supply a handle + app password (created at
# https://bsky.app/settings/app-passwords). We exchange those for an
# accessJwt (~2h) and refreshJwt (~60d), which is what we actually store.
module Bluesky
  class Session
    PDS_URL          = "https://bsky.social"
    CREATE_PATH      = "/xrpc/com.atproto.server.createSession"
    REFRESH_PATH     = "/xrpc/com.atproto.server.refreshSession"
    DEFAULT_EXPIRES  = 2.hours

    Result = Struct.new(:ok?, :did, :handle, :access_jwt, :refresh_jwt, :error, keyword_init: true)

    class << self
      # Stub signature: ->(method, url, payload_or_nil, headers_or_nil) -> { status:, body: }
      attr_accessor :http_stub

      def create(identifier:, password:)
        status, body = post_json(PDS_URL + CREATE_PATH,
          payload: { identifier: identifier, password: password })
        parse(status, body)
      end

      def refresh(refresh_jwt:)
        status, body = post_json(PDS_URL + REFRESH_PATH,
          headers: { "Authorization" => "Bearer #{refresh_jwt}" })
        parse(status, body)
      end

      private

      def post_json(url, payload: nil, headers: {})
        if http_stub
          return http_stub.call(:post, url, payload, headers)
        end
        uri = URI(url)
        req = Net::HTTP::Post.new(uri)
        headers.each { |k, v| req[k] = v }
        if payload
          req["Content-Type"] = "application/json"
          req.body = payload.to_json
        end
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
        body = begin
          JSON.parse(res.body.to_s)
        rescue JSON::ParserError
          {}
        end
        [res.code, body]
      end

      def parse(status, body)
        body ||= {}
        if status == "200" && body["accessJwt"].present?
          Result.new(ok?:         true,
                     did:         body["did"],
                     handle:      body["handle"],
                     access_jwt:  body["accessJwt"],
                     refresh_jwt: body["refreshJwt"])
        else
          msg = body["message"] || body["error"]
          Result.new(ok?: false, error: "HTTP #{status}#{msg ? ": #{msg}" : ""}")
        end
      end
    end
  end
end
