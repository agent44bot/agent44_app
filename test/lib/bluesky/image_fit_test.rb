require "test_helper"

class Bluesky::ImageFitTest < ActiveSupport::TestCase
  LIMIT = Bluesky::UserClient::MAX_IMAGE_BYTES

  test "passes an under-limit image through unchanged (no re-encode)" do
    bytes, mime = Bluesky::ImageFit.fit("small-bytes", "image/png")
    assert_equal "small-bytes", bytes
    assert_equal "image/png", mime, "mime is preserved for pass-through"
  end

  test "downscales an oversized image under the 1MB limit as JPEG" do
    big = Vips::Image.gaussnoise(4000, 4000, sigma: 60).cast("uchar").jpegsave_buffer(Q: 100)
    assert big.bytesize > LIMIT, "fixture should exceed 1MB (was #{big.bytesize})"

    bytes, mime = Bluesky::ImageFit.fit(big, "image/jpeg")
    assert bytes, "expected downscaled bytes"
    assert bytes.bytesize <= LIMIT, "downscaled to #{bytes.bytesize} bytes, still over 1MB"
    assert_equal "image/jpeg", mime
  end

  test "returns nil for blank input" do
    assert_nil Bluesky::ImageFit.fit(nil)
    assert_nil Bluesky::ImageFit.fit("")
  end
end
