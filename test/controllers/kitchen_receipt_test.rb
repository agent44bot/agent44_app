require "test_helper"
require "ostruct"

# Grocery receipt upload + Opus-vision extraction into a price history. The
# extractor is stubbed (never hit the Anthropic API in tests).
class KitchenReceiptTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # What the (stubbed) vision model "reads" off the receipt. Includes a caps
  # name (must be downcased) and a tax line (must be skipped).
  PARSED = {
    "store" => "Wegmans",
    "total" => 42.50,
    "items" => [
      { "raw_label" => "BNLS CHKN BRST", "canonical_name" => "Chicken Breast", "quantity" => 2.0, "unit" => "lb", "unit_price" => 6.99 },
      { "raw_label" => "ROMAINE",        "canonical_name" => "romaine lettuce", "quantity" => 1,   "unit" => "each", "unit_price" => 2.99 },
      { "raw_label" => "TAX",            "canonical_name" => "",               "quantity" => 1,   "unit" => "each", "unit_price" => 3.10 }
    ]
  }.freeze

  setup do
    @user = User.create!(email_address: "receipt-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(@user)
  end

  teardown { KitchenAi::ReceiptExtractor.stub = nil }

  def stub_extractor(payload = PARSED)
    text = OpenStruct.new(text: payload.to_json)
    KitchenAi::ReceiptExtractor.stub = ->(image_bytes:, media_type:, known_names:) {
      OpenStruct.new(content: [ text ], usage: OpenStruct.new(input_tokens: 300, output_tokens: 150))
    }
  end

  def upload!(file: fixture_file_upload("sample_bottle.png", "image/png"))
    post nyk_grocery_receipts_path, params: { from: "2026-06-15", to: "2026-06-21", receipt: file }
  end

  test "upload stores the receipt, attaches the image, and enqueues extraction" do
    assert_difference -> { GroceryReceipt.count }, 1 do
      assert_enqueued_with(job: GroceryReceiptExtractionJob) { upload! }
    end
    receipt = GroceryReceipt.last
    assert receipt.image.attached?
    assert_equal "pending", receipt.status
    assert_equal Date.new(2026, 6, 15), receipt.week_start
    assert_equal @user, receipt.created_by
    assert_redirected_to nyk_list_path
  end

  test "upload without a file is rejected" do
    assert_no_difference -> { GroceryReceipt.count } do
      post nyk_grocery_receipts_path, params: { from: "2026-06-15", to: "2026-06-21" }
    end
    assert_redirected_to nyk_list_path
    assert_equal "Choose a receipt photo or PDF to upload.", flash[:alert]
  end

  test "extraction job parses lines into ingredient_prices and the receipt total" do
    stub_extractor
    perform_enqueued_jobs { upload! }

    receipt = GroceryReceipt.last
    assert_equal "parsed", receipt.reload.status
    assert_equal 4250, receipt.total_cents
    assert_equal "Wegmans", receipt.store
    # Two real lines; the TAX line (blank canonical_name) is skipped.
    assert_equal 2, receipt.ingredient_prices.count
    chicken = receipt.ingredient_prices.find_by(canonical_name: "chicken breast")
    assert_not_nil chicken, "caps name should be normalized to lower-case"
    assert_equal 699, chicken.unit_price_cents
    assert_equal "lb", chicken.unit
    assert_equal receipt.purchased_on, chicken.observed_on
  end

  test "extraction job marks the receipt failed when the model errors" do
    KitchenAi::ReceiptExtractor.stub = ->(image_bytes:, media_type:, known_names:) {
      OpenStruct.new(content: [ OpenStruct.new(text: "not json") ], usage: OpenStruct.new(input_tokens: 1, output_tokens: 1))
    }
    perform_enqueued_jobs { upload! }
    receipt = GroceryReceipt.last
    assert_equal "failed", receipt.reload.status
    assert receipt.parse_error.present?
    assert_equal 0, receipt.ingredient_prices.count
  end
end
