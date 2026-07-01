require "vips"

module Bluesky
  # Squeezes an image under Bluesky's per-blob size limit. Images already under
  # the limit pass through unchanged; larger ones are resized to 1280px on the
  # long edge and re-encoded as a progressively lower quality JPEG until they
  # fit. Returns [bytes, mime] or nil when it cannot get under the limit (the
  # caller then surfaces a clean error / posts text-only).
  #
  # Shared by both Bluesky image paths: the uploaded ActiveStorage attachment
  # (WorkspacePosts::Dispatcher) and the URL-based image (UserClient), so an
  # oversized NY Kitchen event photo no longer fails only on the URL path.
  module ImageFit
    def self.fit(raw, content_type = nil)
      return nil if raw.nil? || raw.bytesize.zero?
      limit = Bluesky::UserClient::MAX_IMAGE_BYTES
      return [ raw, content_type ] if raw.bytesize <= limit

      thumb = Vips::Image.thumbnail_buffer(raw, 1280)
      [ 80, 60, 45, 30 ].each do |q|
        jpeg = thumb.jpegsave_buffer(Q: q, strip: true)
        return [ jpeg, "image/jpeg" ] if jpeg.bytesize <= limit
      end
      nil
    rescue => e
      Rails.logger.warn("Bluesky::ImageFit.fit failed: #{e.class}: #{e.message}")
      nil
    end
  end
end
