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

  test "generate builds an AI draft recipe for the class, billed as nyk_recipe_generate" do
    stub_extractor_success
    post nyk_handouts_path, params: { generate: "1", event_url: EVENT_URL, event_name: "Korean BBQ Class" }
    handout = KitchenHandout.last
    assert_redirected_to edit_nyk_handout_path(handout)
    assert_equal "Korean BBQ Class", handout.title
    assert_equal "generated", handout.source_kind
    assert_equal handout, KitchenHandout.for_event_url(EVENT_URL)
    # Logged under its own billing source so it shows as its own /billing line.
    assert_equal "nyk_recipe_generate", AiCallLog.last.source
    assert_includes AiCallLog::NYK_SOURCES, "nyk_recipe_generate"
  end

  test "new page offers Generate recipe with AI when opened from a class" do
    get new_nyk_handout_path(event_url: EVENT_URL, event_name: "Korean BBQ")
    assert_response :success
    assert_match "Generate recipe with AI", response.body
  end

  test "generate retries once on a transient API error then succeeds" do
    calls = 0
    ok = OpenStruct.new(text: { "recipes" => EXTRACTED }.to_json)
    KitchenAi::RecipeExtractor.stub = lambda do |messages:|
      calls += 1
      raise Anthropic::Errors::APIError.new(url: "https://api", message: "overloaded") if calls == 1
      OpenStruct.new(content: [ ok ], usage: OpenStruct.new(input_tokens: 10, output_tokens: 10))
    end
    result = KitchenAi::RecipeExtractor.new.generate(class_name: "Sushi Rolling")
    assert result.ok?, "should succeed after one retry"
    assert_equal 2, calls
  end

  test "generate shows a friendly message when the API keeps failing" do
    KitchenAi::RecipeExtractor.stub = lambda do |messages:|
      raise Anthropic::Errors::APIError.new(url: "https://api", message: "overloaded")
    end
    result = KitchenAi::RecipeExtractor.new.generate(class_name: "Sushi Rolling")
    assert_not result.ok?
    assert_match(/busy for a moment/, result.error)
  end

  test "reusing an existing packet copies it to the class without calling the AI" do
    source = KitchenHandout.create!(title: "Fresh Pasta Ravioli", data: { "recipes" => EXTRACTED })
    assert_difference "KitchenHandout.count", 1 do
      post nyk_handouts_path, params: { existing_id: source.id, event_url: EVENT_URL }
    end
    copy = KitchenHandout.for_event_url(EVENT_URL)
    assert_redirected_to edit_nyk_handout_path(copy)
    # A copy, not a shared link: the class gets its own new record.
    assert_not_equal source, copy
    assert_equal source.title, copy.title
    assert_equal source.recipes, copy.recipes
    # The source is untouched (still attached to nothing here).
    assert_nil source.links.find_by(event_url: EVENT_URL)
  end

  test "reused copy is independent: editing or deleting it leaves the source alone" do
    source = KitchenHandout.create!(title: "Fresh Pasta Ravioli", data: { "recipes" => EXTRACTED })
    copy = source.copy_to!(EVENT_URL)

    copy.update!(data: { "recipes" => [ EXTRACTED.first.merge("title" => "Changed") ] })
    assert_equal "Fresh Pasta", source.reload.recipes.first["title"]

    copy.destroy!
    assert KitchenHandout.exists?(source.id)
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

  test "update cleans ingredient-name punctuation artifacts and sentence-cases on save" do
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
    assert_equal "Fresh ginger (finely grated)", ings[0]["item"]
    assert_equal "Lemongrass paste (Note 2)", ings[1]["item"]
  end

  test "hide_equipment removes a tag from the palette for all recipes" do
    KitchenHandout.create!(title: "Packet", data: { "recipes" => EXTRACTED, "equipment" => [ "Pasta machine" ] })
    assert_includes KitchenHandout.equipment_catalog, "Pasta machine"
    post nyk_hide_equipment_tag_path, params: { name: "Pasta machine" }
    assert_response :success
    refute_includes KitchenHandout.equipment_catalog, "Pasta machine"
  end

  test "the edit page renders the equipment tag picker with catalog and selected" do
    handout = KitchenHandout.create!(title: "Packet", data: { "recipes" => EXTRACTED, "equipment" => [ "Wooden spoon" ] })
    get edit_nyk_handout_path(handout)
    assert_response :success
    assert_select "[data-controller='equipment-tags']"
    assert_match "data-equipment-tags-selected-value", response.body
    assert_match "Wooden spoon", response.body   # the recipe's current item
    assert_match "Cutting board", response.body   # a starter palette tag
    assert_match "data-equipment-tags-save-url-value", response.body # equipment auto-save wired
  end

  test "update_equipment auto-saves the equipment list without touching recipes" do
    handout = KitchenHandout.create!(title: "Packet", data: { "recipes" => EXTRACTED, "equipment" => [ "Whisk" ] })
    patch nyk_handout_equipment_path(handout), params: { equipment: "Whisk\nCast iron skillet" }
    assert_response :success
    handout.reload
    assert_equal [ "Whisk", "Cast iron skillet" ], handout.equipment
    assert_equal 1, handout.recipes.size # recipes untouched
  end

  test "the Add-recipe page wires the loading spinner on generate and build" do
    get new_nyk_handout_path(event_url: EVENT_URL, event_name: "Macarons")
    assert_response :success
    assert_match "form-spinner", response.body
  end

  test "update saves the per-station equipment list (blank lines dropped) and round-trips it" do
    handout = KitchenHandout.create!(title: "Packet", data: { "recipes" => EXTRACTED })
    patch nyk_handout_path(handout), params: {
      title: "Packet", station_label: "Single station",
      equipment: "Large stockpot\n  Wooden spoon  \n\nWhisk\n",
      recipes: { "0" => {
        title: "Fresh Pasta",
        ingredients: { "0" => { qty: "2 c", station_qty: "1 c", item: "Flour", section: "" } },
        directions: { "0" => { section: "", steps: "Mix." } }
      } }
    }
    handout.reload
    assert_equal [ "Large stockpot", "Wooden spoon", "Whisk" ], handout.equipment
    assert_equal 1, handout.recipes.size

    get edit_nyk_handout_path(handout)
    assert_response :success
    assert_match "Large stockpot", response.body
  end

  test "update keeps blank lines between steps so spacing carries into the PDF" do
    handout = KitchenHandout.create!(title: "Packet", data: { "recipes" => EXTRACTED })
    patch nyk_handout_path(handout), params: {
      title: "Packet", station_label: "Single station",
      recipes: { "0" => {
        title: "Sauce",
        ingredients: { "0" => { qty: "2 T", station_qty: "1 T", item: "Butter", section: "" } },
        # Leading + trailing blanks, an interior blank, and a doubled blank.
        directions: { "0" => { section: "", steps: "\nMelt butter.\nStir in flour.\n\n\nSeason to taste.\n" } }
      } }
    }
    handout.reload
    steps = handout.recipes.first["directions"].first["steps"]
    # Interior blank preserved (as ""), runs collapsed to one, edges trimmed.
    assert_equal [ "Melt butter.", "Stir in flour.", "", "Season to taste." ], steps
  end

  test "the edit textarea round-trips the blank line back into the box" do
    handout = KitchenHandout.create!(title: "Packet", data: { "recipes" => [
      { "title" => "Sauce",
        "ingredients" => [ { "qty" => "2 T", "station_qty" => "1 T", "item" => "Butter", "section" => nil } ],
        "directions" => [ { "section" => nil, "steps" => [ "Melt butter.", "", "Season to taste." ] } ] } ] })
    get edit_nyk_handout_path(handout)
    assert_response :success
    assert_match "Melt butter.\n\nSeason to taste.", response.body
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

  test "the handout PDF embeds the Carlito body font" do
    handout = KitchenHandout.create!(title: "Packet", data: { "recipes" => EXTRACTED })
    get print_nyk_handout_path(handout, format: :pdf)
    assert_response :success
    assert_match(/Carlito/, response.body, "expected the Carlito font to be embedded")
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

  test "new page has no green reuse-suggestion box (removed per Lora) but lists packets to attach" do
    KitchenHandout.create!(title: "Fresh Pasta: Ravioli Workshop 5/14", data: { "recipes" => EXTRACTED })
    get new_nyk_handout_path(event_url: EVENT_URL, event_name: "Fresh Pasta: Ravioli Workshop 8/6/26")
    assert_response :success
    assert_no_match(/Copy this packet to the class/, response.body) # green suggestion gone
    assert_match "Fresh Pasta: Ravioli Workshop 5/14", response.body # still in the attach list
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

  test "destroy from the library returns to the library" do
    handout = KitchenHandout.create!(title: "Packet", data: { "recipes" => EXTRACTED })
    delete nyk_handout_path(handout), params: { return_to: nyk_recipes_path }
    assert_redirected_to nyk_recipes_path
  end

  test "destroy ignores an off-site return_to (no open redirect)" do
    handout = KitchenHandout.create!(title: "Packet", data: { "recipes" => EXTRACTED })
    delete nyk_handout_path(handout), params: { return_to: "https://evil.example.com" }
    assert_redirected_to nyk_list_path
  end

  test "library lists every packet" do
    KitchenHandout.create!(title: "Fresh Pasta", data: { "recipes" => EXTRACTED })
    KitchenHandout.create!(title: "Sourdough Basics", data: { "recipes" => EXTRACTED })
    get nyk_recipes_path
    assert_response :success
    assert_match "Fresh Pasta", response.body
    assert_match "Sourdough Basics", response.body
  end

  SOURDOUGH = [ { "title" => "Sourdough",
    "ingredients" => [ { "qty" => "2 c", "station_qty" => "1 c", "item" => "Rye", "section" => nil } ],
    "directions" => [ { "section" => nil, "steps" => [ "Mix." ] } ] } ].freeze

  test "library search filters by title" do
    KitchenHandout.create!(title: "Fresh Pasta", data: { "recipes" => EXTRACTED })
    KitchenHandout.create!(title: "Sourdough Basics", data: { "recipes" => SOURDOUGH })
    get nyk_recipes_path(q: "pasta")
    assert_response :success
    assert_match "Fresh Pasta", response.body
    assert_no_match(/Sourdough Basics/, response.body)
  end

  test "library search matches an ingredient inside the recipe" do
    KitchenHandout.create!(title: "Fresh Pasta", data: { "recipes" => EXTRACTED }) # has "All-purpose flour"
    KitchenHandout.create!(title: "Sourdough Basics",
      data: { "recipes" => [ { "title" => "Sourdough",
        "ingredients" => [ { "qty" => "2 c", "station_qty" => "1 c", "item" => "Rye", "section" => nil } ],
        "directions" => [ { "section" => nil, "steps" => [ "Mix." ] } ] } ] })
    get nyk_recipes_path(q: "all-purpose flour")
    assert_response :success
    assert_match "Fresh Pasta", response.body
    assert_no_match(/Sourdough Basics/, response.body)
  end

  test "attach picker searches the full library when given a query" do
    KitchenHandout.create!(title: "Fresh Pasta", data: { "recipes" => EXTRACTED })
    KitchenHandout.create!(title: "Sourdough Basics", data: { "recipes" => EXTRACTED })
    get new_nyk_handout_path(event_url: EVENT_URL, event_name: "Whatever", q: "sourdough")
    assert_response :success
    assert_match "Sourdough Basics", response.body
    assert_no_match(/Copy this packet to the class/, response.body) # no similarity suggestion while searching
  end

  SIBLING_URL = "https://nykitchen.com/event/fresh-pasta-ravioli-workshop-9-3-26/".freeze

  test "reusing a packet copies it and auto-links other future runs to the copy" do
    source = KitchenHandout.create!(title: "Fresh Pasta: Ravioli Workshop 8/6/26", data: { "recipes" => EXTRACTED })
    snap = KitchenSnapshot.create!(taken_on: Date.current)
    snap.kitchen_events.create!(name: "Fresh Pasta: Ravioli Workshop 8/6/26", url: EVENT_URL,
                                start_at: 2.weeks.from_now, availability: "InStock")
    snap.kitchen_events.create!(name: "Fresh Pasta: Ravioli Workshop 9/3/26", url: SIBLING_URL,
                                start_at: 5.weeks.from_now, availability: "InStock")

    post nyk_handouts_path, params: { existing_id: source.id, event_url: EVENT_URL }

    # Reuse made a copy and landed on its review page; the sibling future run is
    # auto-linked to that copy, not to the source we reused from.
    copy = KitchenHandout.for_event_url(EVENT_URL)
    assert_not_equal source, copy
    assert_redirected_to edit_nyk_handout_path(copy)
    assert_not KitchenHandoutLink.find_by(event_url: EVENT_URL).auto
    sibling = KitchenHandoutLink.find_by(event_url: SIBLING_URL)
    assert_equal copy, sibling.kitchen_handout
    assert sibling.auto
  end

  test "edit page warns when a packet is shared by more than one class" do
    handout = KitchenHandout.create!(title: "Korean BBQ", data: { "recipes" => EXTRACTED })
    handout.attach_to!("https://nyk/a")
    handout.links.create!(event_url: "https://nyk/b", auto: true)
    get edit_nyk_handout_path(handout)
    assert_response :success
    assert_match "shared by", response.body
    assert_match "2 classes", response.body
  end

  test "edit page does not warn for a single-class packet" do
    handout = KitchenHandout.create!(title: "Korean BBQ", data: { "recipes" => EXTRACTED })
    handout.attach_to!("https://nyk/a")
    get edit_nyk_handout_path(handout)
    assert_response :success
    assert_no_match(/shared by/, response.body)
  end
end
