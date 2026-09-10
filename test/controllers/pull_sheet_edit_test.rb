require "test_helper"
require "ostruct"

# A class's pull sheet is editable in place (Lora and Caitlin, 2026-09-09):
# the sheet autosaves to PullSheetEdit, the edited list replaces the AI one
# on the page, the PDF, and the spreadsheet, and "Reset" drops the edits.
class PullSheetEditTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  FRAME = { "Turbo-Frame" => "grocery_list" }.freeze
  RECIPE = [ { "title" => "Ravioli", "headcount" => 12,
               "ingredients" => [ { "qty" => "2 c", "station_qty" => "1 c", "item" => "Flour", "section" => nil } ],
               "directions" => [ { "section" => nil, "steps" => [ "Mix." ] } ] } ].freeze
  AGG = { "categories" => [ { "name" => "Pantry", "items" => [ { "quantity" => "4 c", "item" => "Flour", "price" => 1.2, "classes" => [ "Ravioli" ] } ] } ],
          "to_taste" => [ "salt" ] }.freeze

  setup do
    travel_to Time.zone.local(2026, 6, 17, 12, 0)
    @user = User.create!(email_address: "ps-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(@user)
    @nyk = nyk_workspace!(owner: @user)
    @snap = KitchenSnapshot.create!(taken_on: Date.current)
    @url = "https://nykitchen.com/event/ps-ravioli/"
    @snap.kitchen_events.create!(name: "Ravioli", url: @url, start_at: 2.days.from_now.change(hour: 18),
                                 availability: "InStock", capacity: 24, spots_left: 12)
    KitchenPacket.create!(title: "Ravioli", data: { "recipes" => RECIPE }).attach_to!(@url)
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    KitchenAi::GroceryAggregator.stub = lambda do |items:|
      OpenStruct.new(content: [ OpenStruct.new(text: AGG.to_json) ], usage: OpenStruct.new(input_tokens: 10, output_tokens: 10))
    end
  end

  teardown do
    KitchenAi::GroceryAggregator.stub = nil
    Rails.cache = @original_cache
  end

  def sheet
    get nyk_grocery_path(event_url: @url, name: "Ravioli"), headers: FRAME
    perform_enqueued_jobs
    get nyk_grocery_path(event_url: @url, name: "Ravioli"), headers: FRAME
    response.body
  end

  def save!(categories, to_taste: [ "salt" ], base_key: "k1")
    patch nyk_pull_sheet_path, params: { event_url: @url, base_key: base_key, categories: categories.to_json, to_taste: to_taste.to_json },
          headers: { "Accept" => "application/json" }
  end

  test "the generated pull sheet renders editable fields, the add controls, and no edited badge" do
    body = sheet
    assert_no_match "data-price", body # the cook-line sheet never carries cost, not even in markup
    assert_match 'data-controller="pull-sheet-editor"', body
    assert_match 'data-field="quantity" class="font-semibold w-24 shrink-0 outline-none', body
    assert_match "+ add item", body
    assert_match "+ add section", body
    assert_no_match "Edited by hand", body
    assert_no_match "Reset to generated list", body
  end

  test "saving an edit replaces the list on the page, the PDF, and the spreadsheet" do
    sheet
    save!([ { name: "Pantry", items: [ { quantity: "5 c", item: "00 flour" }, { quantity: "", item: "" } ] },
            { name: "Dairy", items: [ { quantity: "6", item: "Eggs" } ] } ], to_taste: [ "salt", "pepper" ])
    assert_response :success
    assert_equal 2, JSON.parse(response.body)["items"]

    edit = @nyk.pull_sheet_edits.find_by!(event_url: @url)
    assert_equal [ "Pantry", "Dairy" ], edit.categories.map { |c| c["name"] }
    assert_equal [ { "quantity" => "5 c", "item" => "00 flour" } ], edit.categories[0]["items"] # blank row dropped, no price kept
    assert_equal @user, edit.updated_by

    body = sheet
    assert_match "00 flour", body
    assert_match "Eggs", body
    assert_no_match ">Flour<", body
    assert_match "Edited by hand", body
    assert_match "Reset to generated list", body
    assert_match "salt, pepper", body

    get nyk_grocery_path(event_url: @url, name: "Ravioli", download: 1)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    get nyk_grocery_path(event_url: @url, name: "Ravioli", download: 1, xlsx: 1)
    assert_response :success
    assert_equal KitchenGroceryXlsx::CONTENT_TYPE, response.media_type
    # The xlsx is zipped; read the sheet XML back out to prove the edit is in it.
    require "zip"
    xml = nil
    Zip::File.open_buffer(response.body.b) { |z| xml = z.get_input_stream("xl/worksheets/sheet1.xml").read }
    assert_match "00 flour", xml
  end

  test "an edited sheet shows even when no generated list is cached, without calling the AI" do
    save!([ { name: "Pantry", items: [ { quantity: "1", item: "Thing" } ] } ])
    calls = 0
    KitchenAi::GroceryAggregator.stub = ->(items:) { calls += 1; raise "should not aggregate" }
    get nyk_grocery_path(event_url: @url, name: "Ravioli"), headers: FRAME
    assert_response :success
    assert_match "Thing", response.body
    assert_equal 0, calls
  end

  test "when the recipes change after an edit, the sheet keeps the edits and says so" do
    sheet
    key = @nyk.then { KitchenAi::GroceryList.cache_key(KitchenAi::GroceryList.new.with_recipe(@snap.kitchen_events.to_a), {}) }
    save!([ { name: "Pantry", items: [ { quantity: "1", item: "Kept" } ] } ], base_key: key)
    assert_no_match "recipes changed", sheet
    packet = KitchenPacket.for_event_url(@url)
    packet.update!(data: packet.data.merge("recipes" => [ RECIPE[0].merge("title" => "Ravioli v2") ]))
    body = sheet
    assert_match "Kept", body
    assert_match "recipes or station counts changed", body
  end

  test "reset drops the edits and goes back to the generated list" do
    sheet
    save!([ { name: "Pantry", items: [ { quantity: "1", item: "Mine" } ] } ])
    delete nyk_pull_sheet_path, params: { event_url: @url, name: "Ravioli" }, headers: FRAME
    assert_response :redirect
    assert_nil @nyk.pull_sheet_edits.find_by(event_url: @url)
    body = sheet
    assert_match ">Flour<", body
    assert_no_match "Mine", body
  end

  test "bad input is rejected, and a non-member cannot save" do
    save!("not a list")
    assert_response :unprocessable_entity
    save!([ "not a section" ])
    assert_response :success # junk entries are dropped, not fatal
    patch nyk_pull_sheet_path, params: { categories: "[]" }, headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity

    stranger = User.create!(email_address: "str-#{SecureRandom.hex(3)}@example.com")
    sign_in_as(stranger)
    save!([ { name: "X", items: [] } ])
    assert_response :not_found
  end

  test "the weekly grocery list is not editable" do
    get nyk_grocery_path(generate: 1), headers: FRAME
    perform_enqueued_jobs
    get nyk_grocery_path, headers: FRAME
    assert_no_match 'data-controller="pull-sheet-editor"', response.body
    assert_no_match "+ add item", response.body
  end

  test "deleting the editor nulls the sheet's editor; deleting the workspace removes the sheet" do
    save!([ { name: "Pantry", items: [ { quantity: "1", item: "Thing" } ] } ])
    edit = @nyk.pull_sheet_edits.find_by!(event_url: @url)
    other = User.create!(email_address: "ed-#{SecureRandom.hex(3)}@example.com")
    edit.update!(updated_by: other)
    other.destroy!
    assert_nil edit.reload.updated_by
    @nyk.destroy!
    assert_nil PullSheetEdit.find_by(id: edit.id)
  end
end
