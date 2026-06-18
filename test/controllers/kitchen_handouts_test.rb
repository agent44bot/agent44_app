require "test_helper"
require "ostruct"

# Recipe handouts: AI-extracted printable recipe packets attached to classes
# by event URL from Sam's list page. The extractor is stubbed (never hit the
# Anthropic API in tests).
class KitchenHandoutsTest < ActionDispatch::IntegrationTest
  EXTRACTED = [
    {
      "title" => "Fresh Pasta",
      "ingredients" => [
        { "qty" => "2½ c", "station_qty" => "1¼ c", "item" => "All-purpose flour", "section" => nil },
        { "qty" => "", "station_qty" => "", "item" => "Salt, to taste", "section" => nil }
      ],
      "directions" => [ { "section" => nil, "steps" => [ "Pour flour in a bowl.", "Knead." ] } ]
    }
  ].freeze

  EVENT_URL = "https://nykitchen.com/event/fresh-pasta-ravioli-workshop-8-6-26/".freeze

  setup do
    @user = User.create!(email_address: "handout-#{SecureRandom.hex(4)}@example.com", role: "user")
    sign_in_as(@user)
  end

  teardown do
    KitchenAi::RecipeExtractor.stub = nil
  end

  def stub_extractor_success
    text = OpenStruct.new(text: { "recipes" => EXTRACTED }.to_json)
    KitchenAi::RecipeExtractor.stub = ->(messages:) {
      OpenStruct.new(content: [ text ], usage: OpenStruct.new(input_tokens: 100, output_tokens: 200))
    }
  end

  test "create extracts recipes, saves the handout, and links the class" do
    stub_extractor_success
    post nyk_handouts_path, params: {
      event_url: EVENT_URL, event_name: "Fresh Pasta: Ravioli Workshop 8/6/26",
      recipe_text: "Fresh Pasta... 2 1/2 c flour..."
    }

    handout = KitchenHandout.last
    assert_redirected_to edit_nyk_handout_path(handout)
    assert_equal "Fresh Pasta: Ravioli Workshop 8/6/26", handout.title
    assert_equal "1¼ c", handout.recipes.first["ingredients"].first["station_qty"]
    assert_equal handout, KitchenHandout.for_event_url(EVENT_URL)
    assert handout.extract_cost_cents.to_i.positive?, "captures the Opus extraction cost"
    assert_match(/cost \$/, handout.extract_cost_label)
  end

  test "create with empty input bounces back with an error" do
    post nyk_handouts_path, params: { event_url: EVENT_URL, event_name: "X", recipe_text: "" }
    assert_redirected_to new_nyk_handout_path(event_url: EVENT_URL, event_name: "X")
    assert_match(/Paste a recipe/, flash[:alert])
    assert_equal 0, KitchenHandout.count
  end

  test "reusing an existing packet links it without calling the AI" do
    handout = KitchenHandout.create!(title: "Fresh Pasta Ravioli", data: { "recipes" => EXTRACTED })
    post nyk_handouts_path, params: { existing_id: handout.id, event_url: EVENT_URL }
    assert_redirected_to nyk_list_path
    assert_equal handout, KitchenHandout.for_event_url(EVENT_URL)
  end

  test "attaching moves the link when the class already had a packet" do
    old = KitchenHandout.create!(title: "Old", data: { "recipes" => EXTRACTED })
    old.attach_to!(EVENT_URL)
    new_h = KitchenHandout.create!(title: "New", data: { "recipes" => EXTRACTED })
    new_h.attach_to!(EVENT_URL)
    assert_equal new_h, KitchenHandout.for_event_url(EVENT_URL)
  end

  test "update parses the review form and drops blank ingredient rows" do
    handout = KitchenHandout.create!(title: "Packet", data: { "recipes" => EXTRACTED })
    patch nyk_handout_path(handout), params: {
      title: "Packet", station_label: "Single station",
      recipes: {
        "0" => {
          title: "Fresh Pasta",
          ingredients: {
            "0" => { qty: "2½ c", station_qty: "1¼ c", item: "All-purpose flour", section: "" },
            "1" => { qty: "", station_qty: "", item: "", section: "" } # spare row
          },
          directions: { "0" => { section: "", steps: "Pour flour in a bowl.\nKnead." } }
        }
      }
    }
    assert_redirected_to edit_nyk_handout_path(handout)
    handout.reload
    assert_equal 1, handout.recipes.first["ingredients"].size
    assert_equal [ "Pour flour in a bowl.", "Knead." ], handout.recipes.first["directions"].first["steps"]
  end

  test "update standardizes measurement units on save (Lora's house style)" do
    handout = KitchenHandout.create!(title: "Packet", data: { "recipes" => EXTRACTED })
    patch nyk_handout_path(handout), params: {
      title: "Packet", station_label: "Single station",
      recipes: {
        "0" => {
          title: "Fresh Pasta",
          ingredients: {
            "0" => { qty: "2 Tablespoons", station_qty: "1 tablespoon", item: "Olive oil", section: "" },
            "1" => { qty: "1/2 cup", station_qty: "1/4 cup", item: "Flour", section: "" }
          },
          directions: { "0" => { section: "", steps: "Mix." } }
        }
      }
    }
    handout.reload
    ings = handout.recipes.first["ingredients"]
    assert_equal "2 T", ings[0]["qty"]
    assert_equal "1 T", ings[0]["station_qty"]
    assert_equal "1/2 c", ings[1]["qty"]
    assert_equal "1/4 c", ings[1]["station_qty"]
  end

  test "update cleans ingredient-name punctuation artifacts on save" do
    handout = KitchenHandout.create!(title: "Packet", data: { "recipes" => EXTRACTED })
    patch nyk_handout_path(handout), params: {
      title: "Packet", station_label: "Single station",
      recipes: {
        "0" => {
          title: "Thai Green Curry",
          ingredients: {
            "0" => { qty: "1 tsp", station_qty: "1/2 tsp", item: "fresh ginger (, finely grated)", section: "" },
            "1" => { qty: "1 1/2 tsp", station_qty: "3/4 tsp", item: "lemongrass paste ((Note 2))", section: "" }
          },
          directions: { "0" => { section: "", steps: "Mix." } }
        }
      }
    }
    handout.reload
    ings = handout.recipes.first["ingredients"]
    assert_equal "fresh ginger (finely grated)", ings[0]["item"]
    assert_equal "lemongrass paste (Note 2)", ings[1]["item"]
  end

  test "saving an edit busts the preview cache and serves a fresh PDF" do
    handout = KitchenHandout.create!(title: "Packet", data: { "recipes" => EXTRACTED })

    # The edit page's PDF preview iframe carries a cache-busting ?v= param.
    get edit_nyk_handout_path(handout)
    assert_response :success
    before_src = css_select("iframe[title='Recipe PDF preview']").first["src"]
    before_v   = Rack::Utils.parse_nested_query(URI(before_src).query)["v"]
    assert before_v.present?, "preview iframe must carry a cache-busting v param"

    # Baseline: 1 recipe -> full + station = 2 pages.
    get before_src
    before_pages = response.body.scan("/Type /Page\n").size + response.body.scan("/Type /Page ").size
    assert_equal 2, before_pages

    # "Save & refresh preview" with an added recipe (travel so updated_at advances).
    travel 1.second do
      patch nyk_handout_path(handout), params: {
        title: "Packet", station_label: "Single station",
        recipes: {
          "0" => { title: "Fresh Pasta",
                   ingredients: { "0" => { qty: "2½ c", station_qty: "1¼ c", item: "All-purpose flour", section: "" } },
                   directions: { "0" => { section: "", steps: "Mix." } } },
          "1" => { title: "Sauce",
                   ingredients: { "0" => { qty: "2 T", station_qty: "1 T", item: "Butter", section: "" } },
                   directions: { "0" => { section: "", steps: "Melt." } } }
        }
      }
    end
    assert_redirected_to edit_nyk_handout_path(handout)

    # The refreshed edit page points the iframe at a NEW url (so the browser
    # refetches instead of showing the cached PDF)...
    get edit_nyk_handout_path(handout)
    after_src = css_select("iframe[title='Recipe PDF preview']").first["src"]
    after_v   = Rack::Utils.parse_nested_query(URI(after_src).query)["v"]
    assert_not_equal before_v, after_v,
                     "preview URL must change after a save so the browser refetches the PDF"

    # ...and that PDF reflects the edit: 2 recipes -> full + station = 4 pages.
    get after_src
    assert_response :success
    assert_equal "application/pdf", response.media_type
    after_pages = response.body.scan("/Type /Page\n").size + response.body.scan("/Type /Page ").size
    assert_equal 4, after_pages
  end

  test "print page embeds the recipe PDF" do
    handout = KitchenHandout.create!(title: "Packet", data: { "recipes" => EXTRACTED })
    get print_nyk_handout_path(handout)
    assert_response :success
    assert_match print_nyk_handout_path(handout, format: :pdf), response.body
    assert_match "Packet", response.body
  end

  test "print.pdf streams a branded recipe PDF" do
    handout = KitchenHandout.create!(title: "Packet", data: { "recipes" => EXTRACTED })
    get print_nyk_handout_path(handout, format: :pdf)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert response.body.start_with?("%PDF"), "expected PDF bytes"
    # 1 recipe x (full + station) = 2 content pages.
    assert_equal 2, response.body.scan("/Type /Page\n").size + response.body.scan("/Type /Page ").size
  end

  test "create from a recipe URL builds and links a handout" do
    stub_extractor_success
    post nyk_handouts_path, params: {
      event_url: EVENT_URL, event_name: "Fresh Pasta: Ravioli Workshop 8/6/26",
      recipe_url: "https://example.com/recipes/fresh-pasta"
    }
    handout = KitchenHandout.last
    assert_redirected_to edit_nyk_handout_path(handout)
    assert_equal "url", handout.source_kind
    assert_equal "https://example.com/recipes/fresh-pasta", handout.source_url
    assert_equal handout, KitchenHandout.for_event_url(EVENT_URL)
  end

  test "new page renders the drag-and-drop PDF zone with the pdf input intact" do
    get new_nyk_handout_path
    assert_response :success
    assert_select "[data-controller='dropzone']"
    assert_select "input[type=file][name=pdf][data-dropzone-target=input]"
    assert_match "drag it here", response.body
  end

  test "new page suggests a similarly named existing packet" do
    KitchenHandout.create!(title: "Fresh Pasta: Ravioli Workshop 5/14", data: { "recipes" => EXTRACTED })
    KitchenHandout.create!(title: "Sourdough Basics", data: { "recipes" => EXTRACTED })
    get new_nyk_handout_path(event_url: EVENT_URL, event_name: "Fresh Pasta: Ravioli Workshop 8/6/26")
    assert_response :success
    assert_match "Reuse this packet", response.body
    assert_match "Fresh Pasta: Ravioli Workshop 5/14", response.body
  end

  test "signed-out users cannot reach handout pages" do
    delete session_path rescue nil
    reset!
    get new_nyk_handout_path
    assert_response :redirect
  end

  test "list page shows edit link for linked classes and add link otherwise" do
    handout = KitchenHandout.create!(title: "Packet", data: { "recipes" => EXTRACTED })
    handout.attach_to!(EVENT_URL)
    snapshot = KitchenSnapshot.create!(taken_on: Date.current)
    snapshot.kitchen_events.create!(name: "Fresh Pasta: Ravioli Workshop 8/6/26", url: EVENT_URL,
                                    start_at: 2.weeks.from_now, availability: "InStock")
    snapshot.kitchen_events.create!(name: "Sourdough Basics", url: "https://nykitchen.com/event/sourdough/",
                                    start_at: 3.weeks.from_now, availability: "InStock")

    get "/nykitchen/list"
    assert_response :success
    # Linked class: the recipe slot is "Edit" (printing lives on the edit
    # screen), not a direct Print link, so the slot means the same in both
    # states.
    assert_select "a[href=?]", edit_nyk_handout_path(handout)
    assert_no_match print_nyk_handout_path(handout), response.body
    # Unlinked class: an "Add" link to start a recipe. & is HTML-escaped in the
    # rendered href, so match on the escaped form.
    assert_match ERB::Util.html_escape(new_nyk_handout_path(event_url: "https://nykitchen.com/event/sourdough/", event_name: "Sourdough Basics")), response.body
  end

  test "print and edit allow same-origin framing for the PDF preview" do
    handout = KitchenHandout.create!(title: "Packet", data: { "recipes" => EXTRACTED })

    get print_nyk_handout_path(handout, format: :pdf)
    assert_equal "SAMEORIGIN", response.headers["X-Frame-Options"]
    assert_match "frame-ancestors 'self'", response.headers["Content-Security-Policy"].to_s

    get edit_nyk_handout_path(handout)
    assert_equal "SAMEORIGIN", response.headers["X-Frame-Options"]
    assert_match "frame-ancestors 'self'", response.headers["Content-Security-Policy"].to_s
  end

  test "destroy removes the handout and its class link" do
    handout = KitchenHandout.create!(title: "Packet", data: { "recipes" => EXTRACTED })
    handout.attach_to!(EVENT_URL)
    delete nyk_handout_path(handout)
    assert_redirected_to nyk_list_path
    assert_not KitchenHandout.exists?(handout.id)
    assert_nil KitchenHandout.for_event_url(EVENT_URL)
  end
end
