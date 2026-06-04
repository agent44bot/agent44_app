require "test_helper"

class InventoryControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "inv-#{SecureRandom.hex(4)}@example.com", role: "user")
  end

  test "unauthenticated request bounces to sign-in" do
    get "/nykitchen/inventory"
    assert_redirected_to %r{/sign_in}
  end

  test "signed-in user sees the stock page" do
    sign_in_as(@user)
    get "/nykitchen/inventory"
    assert_response :success
    assert_match(/Storage Room/i, response.body)
  end

  test "every inventory page renders" do
    sign_in_as(@user)
    item = InventoryItem.create!(name: "Page Test", units_per_case: 12)
    item.movements.create!(direction: "in", quantity: 3)
    [
      "/nykitchen/inventory",
      "/nykitchen/inventory/receive",
      "/nykitchen/inventory/remove",
      "/nykitchen/inventory/import",
      "/nykitchen/inventory/items/new",
      nyk_inventory_item_path(item),
      edit_nyk_inventory_item_path(item)
    ].each do |path|
      get path
      assert_response :success, "expected 200 for #{path}"
    end
  end

  test "the NYK hub still renders with the Cellar card" do
    sign_in_as(@user)
    InventoryItem.create!(name: "Hub Test", units_per_case: 12).movements.create!(direction: "in", quantity: 4)
    get "/nykitchen"
    assert_response :success
    assert_match(/Cellar/, response.body)
    assert_match(/bottles on hand/, response.body)
  end

  test "lookup by code returns the found item with case default" do
    sign_in_as(@user)
    item = InventoryItem.create!(name: "Rosé", barcode: "111", case_barcode: "999", units_per_case: 12)
    get "/nykitchen/inventory/lookup", params: { code: "999" }
    body = JSON.parse(response.body)
    assert body["found"]
    assert_equal item.id, body["item"]["id"]
    assert_equal 12, body["item"]["default_in"] # scanning the case → a full case
  end

  test "lookup of an unknown code is not found" do
    sign_in_as(@user)
    get "/nykitchen/inventory/lookup", params: { code: "nope" }
    refute JSON.parse(response.body)["found"]
  end

  test "lookup by q searches names" do
    sign_in_as(@user)
    InventoryItem.create!(name: "Whispering Angel", units_per_case: 12)
    get "/nykitchen/inventory/lookup", params: { q: "whisper" }
    assert_equal 1, JSON.parse(response.body)["results"].size
  end

  test "receiving a known item records an in movement" do
    sign_in_as(@user)
    item = InventoryItem.create!(name: "Gin", barcode: "222", units_per_case: 6)
    assert_difference -> { item.movements.count }, 1 do
      post "/nykitchen/inventory/movements",
           params: { item_id: item.id, direction: "in", quantity: 6 }, as: :json
    end
    assert_response :success
    assert_equal 6, item.reload.on_hand
  end

  test "removing draws the count down" do
    sign_in_as(@user)
    item = InventoryItem.create!(name: "Gin", units_per_case: 6)
    item.movements.create!(direction: "in", quantity: 6)
    post "/nykitchen/inventory/movements",
         params: { item_id: item.id, direction: "out", quantity: 2 }, as: :json
    assert_response :success
    assert_equal 4, item.reload.on_hand
  end

  test "receiving an unknown code creates the item inline" do
    sign_in_as(@user)
    assert_difference -> { InventoryItem.count }, 1 do
      post "/nykitchen/inventory/movements", params: {
        direction: "in", code: "777",
        item: { name: "New Cab", category: "wine", units_per_case: 12, case_barcode: "777" },
        quantity: 12
      }, as: :json
    end
    item = InventoryItem.find_by(case_barcode: "777")
    assert_equal "New Cab", item.name
    assert_equal 12, item.on_hand
  end

  test "a movement is attributed to the signed-in user" do
    sign_in_as(@user)
    item = InventoryItem.create!(name: "Gin", units_per_case: 6)
    post "/nykitchen/inventory/movements",
         params: { item_id: item.id, direction: "in", quantity: 1 }, as: :json
    assert_equal @user.id, item.movements.last.user_id
  end

  test "removing an unknown item errors instead of creating" do
    sign_in_as(@user)
    post "/nykitchen/inventory/movements",
         params: { code: "doesnotexist", direction: "out", quantity: 1 }, as: :json
    assert_response :unprocessable_entity
    refute JSON.parse(response.body)["ok"]
  end

  test "CSV import seeds the catalog and opening balances" do
    sign_in_as(@user)
    csv = "name,category,quantity,barcode,par\nMalbec,wine,24,abc123,6\nVodka,spirit,5,,\n"
    tmp = Tempfile.new([ "stock", ".csv" ])
    tmp.write(csv); tmp.rewind
    upload = Rack::Test::UploadedFile.new(tmp.path, "text/csv")

    assert_difference -> { InventoryItem.count }, 2 do
      post "/nykitchen/inventory/import", params: { file: upload }
    end
    assert_redirected_to nyk_inventory_path

    malbec = InventoryItem.find_by(name: "Malbec")
    assert_equal 24, malbec.on_hand
    assert_equal 6, malbec.par_level
    assert_equal "abc123", malbec.barcode
    assert_equal 5, InventoryItem.find_by(name: "Vodka").on_hand
  ensure
    tmp&.close!
  end

  test "creating a catalog item via the form" do
    sign_in_as(@user)
    assert_difference -> { InventoryItem.count }, 1 do
      post "/nykitchen/inventory/items",
           params: { item: { name: "Tequila", category: "spirit", units_per_case: 12 } }
    end
    assert_redirected_to nyk_inventory_item_path(InventoryItem.last)
  end

  # ── Photo + price capture log ──────────────────────────────────────────────
  test "capture log page renders" do
    sign_in_as(@user)
    get "/nykitchen/inventory/captures"
    assert_response :success
    assert_match(/Log a product/i, response.body)
  end

  test "logging a product with a photo creates a capture" do
    sign_in_as(@user)
    photo = fixture_file_upload("sample_bottle.png", "image/png")
    assert_difference -> { InventoryCapture.count }, 1 do
      post "/nykitchen/inventory/captures",
           params: { capture: { name: "Whispering Angel", category: "wine", quantity: 6, unit_price: "18.50", photo: photo } }
    end
    c = InventoryCapture.order(:id).last
    assert c.photo.attached?
    assert_equal @user.id, c.user_id
    assert_in_delta 111.0, c.line_total, 0.001 # 6 * 18.50
    assert_redirected_to nyk_inventory_captures_path
  end

  test "logging without a photo works (photo optional)" do
    sign_in_as(@user)
    assert_difference -> { InventoryCapture.count }, 1 do
      post "/nykitchen/inventory/captures", params: { capture: { category: "beer", quantity: 24, unit_price: "1.20" } }
    end
    refute InventoryCapture.order(:id).last.photo.attached?
  end

  test "CSV export returns the month's rows" do
    sign_in_as(@user)
    InventoryCapture.create!(category: "spirit", name: "Tito's", quantity: 2, unit: "bottle", unit_price: 22.0,
                             captured_at: Time.current, user: @user)
    get "/nykitchen/inventory/captures/export", params: { month: Date.current.strftime("%Y-%m"), format: :csv }
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/Date,Category,Product,Quantity,Unit,Unit price,Line total/, response.body)
    assert_match(/Tito's,2,bottle,22.00,44.00/, response.body)
  end

  test "capture log scopes to the selected month" do
    sign_in_as(@user)
    InventoryCapture.create!(category: "wine", name: "ThisMonth", quantity: 1, captured_at: Time.current, user: @user)
    InventoryCapture.create!(category: "wine", name: "OldOne",   quantity: 1, captured_at: 2.months.ago, user: @user)
    get "/nykitchen/inventory/captures"
    assert_response :success
    assert_match(/ThisMonth/, response.body)
    refute_match(/OldOne/, response.body)
  end

  test "capture records a destination and includes it in the CSV" do
    sign_in_as(@user)
    post "/nykitchen/inventory/captures",
         params: { capture: { name: "Pinot Noir", category: "wine", quantity: 3, unit_price: "10.00", destination: "Tasting Room" } }
    assert_equal "Tasting Room", InventoryCapture.order(:id).last.destination
    get "/nykitchen/inventory/captures/export", params: { month: Date.current.strftime("%Y-%m"), format: :csv }
    assert_match(/Destination/, response.body)
    assert_match(/Tasting Room/, response.body)
  end

  test "deleting a logged capture removes it (and its photo)" do
    sign_in_as(@user)
    c = InventoryCapture.create!(category: "wine", name: "Oops dupe", quantity: 1, captured_at: Time.current, user: @user)
    c.photo.attach(fixture_file_upload("sample_bottle.png", "image/png"))
    assert c.photo.attached?
    assert_difference -> { InventoryCapture.count }, -1 do
      delete "/nykitchen/inventory/captures/#{c.id}"
    end
    assert_redirected_to nyk_inventory_captures_path
  end
end
