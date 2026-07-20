# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_20_181504) do
  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_memories", force: :cascade do |t|
    t.integer "agent_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.string "filename"
    t.datetime "occurred_at"
    t.string "source"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["agent_id", "filename"], name: "index_agent_memories_on_agent_id_and_filename", unique: true
    t.index ["agent_id", "occurred_at"], name: "index_agent_memories_on_agent_id_and_occurred_at"
    t.index ["agent_id"], name: "index_agent_memories_on_agent_id"
  end

  create_table "agent_messages", force: :cascade do |t|
    t.string "agent", default: "ripley", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.string "role", default: "user", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_agent_messages_on_created_at"
    t.index ["status"], name: "index_agent_messages_on_status"
  end

  create_table "agents", force: :cascade do |t|
    t.string "avatar_color", default: "orange", null: false
    t.datetime "created_at", null: false
    t.string "current_task"
    t.text "description"
    t.text "identity_markdown"
    t.datetime "last_active_at"
    t.string "llm_model"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "role", null: false
    t.string "schedule"
    t.json "skills", default: [], null: false
    t.string "slug", null: false
    t.text "soul_markdown"
    t.string "status", default: "offline", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_agents_on_name", unique: true
    t.index ["position"], name: "index_agents_on_position"
    t.index ["slug"], name: "index_agents_on_slug", unique: true
  end

  create_table "ai_call_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "input_tokens", default: 0, null: false
    t.string "model", null: false
    t.integer "output_tokens", default: 0, null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.integer "workspace_id"
    t.index ["created_at"], name: "index_ai_call_logs_on_created_at"
    t.index ["source"], name: "index_ai_call_logs_on_source"
    t.index ["user_id"], name: "index_ai_call_logs_on_user_id"
    t.index ["workspace_id"], name: "index_ai_call_logs_on_workspace_id"
  end

  create_table "apply_requests", force: :cascade do |t|
    t.datetime "applied_at"
    t.datetime "created_at", null: false
    t.datetime "filled_at"
    t.integer "job_id", null: false
    t.text "notes"
    t.datetime "opened_at"
    t.datetime "requested_at"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.index ["job_id"], name: "index_apply_requests_on_job_id", unique: true
    t.index ["status"], name: "index_apply_requests_on_status"
  end

  create_table "connect_chat_messages", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.string "platform", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.integer "workspace_id", null: false
    t.index ["user_id"], name: "index_connect_chat_messages_on_user_id"
    t.index ["workspace_id", "created_at"], name: "index_connect_chat_messages_on_workspace_id_and_created_at"
    t.index ["workspace_id"], name: "index_connect_chat_messages_on_workspace_id"
  end

  create_table "credentials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.datetime "last_used_at"
    t.string "nickname"
    t.string "public_key", null: false
    t.bigint "sign_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["external_id"], name: "index_credentials_on_external_id", unique: true
    t.index ["user_id"], name: "index_credentials_on_user_id"
  end

  create_table "device_tokens", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "platform", default: "ios", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["token"], name: "index_device_tokens_on_token", unique: true
    t.index ["user_id"], name: "index_device_tokens_on_user_id"
  end

  create_table "expenses", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.text "business_purpose"
    t.string "category"
    t.datetime "created_at", null: false
    t.boolean "excluded", default: false, null: false
    t.string "fingerprint", null: false
    t.date "incurred_on", null: false
    t.string "raw_description"
    t.string "review_flag"
    t.string "source", default: "manual", null: false
    t.integer "tax_year", null: false
    t.datetime "updated_at", null: false
    t.string "vendor", null: false
    t.index ["fingerprint"], name: "index_expenses_on_fingerprint", unique: true
    t.index ["tax_year"], name: "index_expenses_on_tax_year"
  end

  create_table "fleet_requests", force: :cascade do |t|
    t.datetime "contacted_at"
    t.datetime "created_at", null: false
    t.text "notes"
    t.text "services", default: "", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["created_at"], name: "index_fleet_requests_on_created_at"
    t.index ["status"], name: "index_fleet_requests_on_status"
    t.index ["user_id"], name: "index_fleet_requests_on_user_id"
  end

  create_table "grocery_receipts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.text "notes"
    t.text "parse_error"
    t.date "purchased_on"
    t.string "status", default: "pending", null: false
    t.string "store"
    t.integer "total_cents"
    t.datetime "updated_at", null: false
    t.date "week_end"
    t.date "week_start"
    t.index ["created_by_id"], name: "index_grocery_receipts_on_created_by_id"
  end

  create_table "hidden_jobs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "job_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["job_id"], name: "index_hidden_jobs_on_job_id"
    t.index ["user_id", "job_id"], name: "index_hidden_jobs_on_user_id_and_job_id", unique: true
    t.index ["user_id"], name: "index_hidden_jobs_on_user_id"
  end

  create_table "impersonation_logs", force: :cascade do |t|
    t.integer "actor_id", null: false
    t.datetime "created_at", null: false
    t.string "event", null: false
    t.string "ip_address"
    t.integer "target_id", null: false
    t.index ["actor_id"], name: "index_impersonation_logs_on_actor_id"
    t.index ["created_at"], name: "index_impersonation_logs_on_created_at"
    t.index ["target_id"], name: "index_impersonation_logs_on_target_id"
  end

  create_table "ingredient_prices", force: :cascade do |t|
    t.string "canonical_name", null: false
    t.datetime "created_at", null: false
    t.integer "grocery_receipt_id"
    t.date "observed_on", null: false
    t.decimal "quantity", precision: 10, scale: 2
    t.string "raw_label"
    t.string "unit"
    t.integer "unit_price_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["canonical_name", "observed_on"], name: "index_ingredient_prices_on_canonical_name_and_observed_on"
    t.index ["grocery_receipt_id"], name: "index_ingredient_prices_on_grocery_receipt_id"
  end

  create_table "inventory_captures", force: :cascade do |t|
    t.datetime "captured_at", null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.string "destination"
    t.string "name"
    t.text "note"
    t.integer "quantity", default: 1, null: false
    t.string "unit"
    t.decimal "unit_price", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["captured_at"], name: "index_inventory_captures_on_captured_at"
    t.index ["user_id"], name: "index_inventory_captures_on_user_id"
  end

  create_table "inventory_items", force: :cascade do |t|
    t.string "barcode"
    t.string "case_barcode"
    t.string "category"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "notes"
    t.integer "par_level"
    t.string "producer"
    t.string "size"
    t.integer "units_per_case", default: 12, null: false
    t.datetime "updated_at", null: false
    t.string "vendor"
    t.string "vintage"
    t.index ["barcode"], name: "index_inventory_items_on_barcode", unique: true
    t.index ["case_barcode"], name: "index_inventory_items_on_case_barcode", unique: true
  end

  create_table "inventory_movements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "direction", null: false
    t.integer "inventory_item_id", null: false
    t.text "note"
    t.datetime "occurred_at", null: false
    t.integer "quantity", default: 1, null: false
    t.string "scanned_code"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["inventory_item_id", "occurred_at"], name: "index_inventory_movements_on_inventory_item_id_and_occurred_at"
    t.index ["inventory_item_id"], name: "index_inventory_movements_on_inventory_item_id"
    t.index ["occurred_at"], name: "index_inventory_movements_on_occurred_at"
    t.index ["user_id"], name: "index_inventory_movements_on_user_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.integer "base_fee_cents", default: 0, null: false
    t.integer "base_fee_configured_cents", default: 0, null: false
    t.boolean "base_fee_waived", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "discount_cents", default: 0, null: false
    t.decimal "discount_percent", precision: 5, scale: 2, default: "0.0", null: false
    t.text "line_items"
    t.decimal "multiplier", precision: 6, scale: 2, default: "1.0", null: false
    t.datetime "paid_at"
    t.date "period_end", null: false
    t.date "period_start", null: false
    t.datetime "sent_at"
    t.string "status", default: "unpaid", null: false
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "usage_cost_cents", default: 0, null: false
    t.integer "workspace_id", null: false
    t.index ["workspace_id", "period_start"], name: "index_invoices_on_workspace_id_and_period_start", unique: true
    t.index ["workspace_id"], name: "index_invoices_on_workspace_id"
  end

  create_table "job_matches", force: :cascade do |t|
    t.datetime "computed_at"
    t.text "cover_letter"
    t.datetime "cover_letter_at"
    t.datetime "created_at", null: false
    t.datetime "enriched_at"
    t.boolean "is_dream", default: false, null: false
    t.integer "job_id", null: false
    t.json "lead_skills"
    t.json "matched_skills"
    t.text "pitch"
    t.json "reasons"
    t.integer "score", default: 0, null: false
    t.datetime "updated_at", null: false
    t.text "why"
    t.index ["job_id"], name: "index_job_matches_on_job_id", unique: true
    t.index ["score"], name: "index_job_matches_on_score"
  end

  create_table "job_sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id"
    t.integer "job_id", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["job_id", "source"], name: "index_job_sources_on_job_id_and_source", unique: true
    t.index ["job_id"], name: "index_job_sources_on_job_id"
    t.index ["source", "url"], name: "index_job_sources_on_source_and_url", unique: true
  end

  create_table "jobs", force: :cascade do |t|
    t.boolean "active", default: true
    t.boolean "ai_augmented", default: false, null: false
    t.string "category", null: false
    t.string "company"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "external_id"
    t.float "latitude"
    t.string "location"
    t.float "longitude"
    t.string "normalized_company"
    t.string "normalized_title"
    t.datetime "posted_at"
    t.string "role_class", default: "traditional", null: false
    t.string "salary"
    t.string "source"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["category"], name: "index_jobs_on_category"
    t.index ["normalized_company", "normalized_title"], name: "index_jobs_on_normalized_company_and_normalized_title"
    t.index ["posted_at"], name: "index_jobs_on_posted_at"
    t.index ["role_class"], name: "index_jobs_on_role_class"
    t.index ["source", "url"], name: "index_jobs_on_source_and_url", unique: true
  end

  create_table "keypair_auth_challenges", force: :cascade do |t|
    t.string "challenge"
    t.boolean "consumed"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "pubkey_hex"
    t.datetime "updated_at", null: false
  end

  create_table "kitchen_events", force: :cascade do |t|
    t.string "availability"
    t.integer "capacity"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "end_at"
    t.string "image_url"
    t.string "instructor"
    t.integer "kitchen_snapshot_id", null: false
    t.integer "last_known_capacity"
    t.integer "last_known_spots_left"
    t.text "menu"
    t.string "name"
    t.string "price"
    t.integer "spots_left"
    t.datetime "start_at"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.string "venue"
    t.index ["kitchen_snapshot_id", "url"], name: "index_kitchen_events_on_kitchen_snapshot_id_and_url", unique: true
    t.index ["kitchen_snapshot_id"], name: "index_kitchen_events_on_kitchen_snapshot_id"
  end

  create_table "kitchen_manual_classes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.datetime "end_at"
    t.string "name", null: false
    t.text "notes"
    t.string "price"
    t.datetime "start_at", null: false
    t.datetime "updated_at", null: false
    t.string "venue"
    t.index ["created_by_id"], name: "index_kitchen_manual_classes_on_created_by_id"
    t.index ["start_at"], name: "index_kitchen_manual_classes_on_start_at"
  end

  create_table "kitchen_packet_links", force: :cascade do |t|
    t.boolean "auto", default: false, null: false
    t.datetime "created_at", null: false
    t.string "event_url", null: false
    t.integer "kitchen_packet_id", null: false
    t.datetime "updated_at", null: false
    t.index ["event_url"], name: "index_kitchen_packet_links_on_event_url", unique: true
    t.index ["kitchen_packet_id"], name: "index_kitchen_packet_links_on_kitchen_packet_id"
  end

  create_table "kitchen_packets", force: :cascade do |t|
    t.string "build_stage"
    t.datetime "created_at", null: false
    t.json "data", default: {}, null: false
    t.integer "extract_cost_cents"
    t.text "extract_error"
    t.string "source_kind"
    t.text "source_text"
    t.string "source_url"
    t.string "station_label", default: "Single station", null: false
    t.string "status", default: "ready", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
  end

  create_table "kitchen_snapshots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "taken_on", null: false
    t.datetime "updated_at", null: false
    t.index ["taken_on"], name: "index_kitchen_snapshots_on_taken_on", unique: true
  end

  create_table "kitchen_ticket_digests", force: :cascade do |t|
    t.integer "change_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.json "entries", default: [], null: false
    t.integer "kitchen_snapshot_id", null: false
    t.integer "sold_out_count", default: 0, null: false
    t.integer "total_tickets", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_kitchen_ticket_digests_on_created_at"
    t.index ["kitchen_snapshot_id"], name: "index_kitchen_ticket_digests_on_kitchen_snapshot_id"
  end

  create_table "kv_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_kv_settings_on_key", unique: true
  end

  create_table "link_scans", force: :cascade do |t|
    t.string "referrer"
    t.datetime "scanned_at", null: false
    t.string "source"
    t.integer "tracked_link_id", null: false
    t.string "user_agent"
    t.index ["scanned_at"], name: "index_link_scans_on_scanned_at"
    t.index ["tracked_link_id"], name: "index_link_scans_on_tracked_link_id"
  end

  create_table "login_codes", force: :cascade do |t|
    t.integer "attempt_count", default: 0, null: false
    t.string "code_digest", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.datetime "expires_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_login_codes_on_email_address"
    t.index ["expires_at"], name: "index_login_codes_on_expires_at"
  end

  create_table "news_articles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "published_at"
    t.string "source", null: false
    t.text "summary"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.datetime "used_at"
    t.index ["source"], name: "index_news_articles_on_source"
    t.index ["url"], name: "index_news_articles_on_url", unique: true
    t.index ["used_at"], name: "index_news_articles_on_used_at"
  end

  create_table "news_digests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.text "summary", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_news_digests_on_date", unique: true
  end

  create_table "notifications", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "level", default: "info", null: false
    t.datetime "read_at"
    t.string "source", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.integer "user_id"
    t.index ["created_at"], name: "index_notifications_on_created_at"
    t.index ["level"], name: "index_notifications_on_level"
    t.index ["read_at"], name: "index_notifications_on_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "page_views", force: :cascade do |t|
    t.string "browser"
    t.string "city"
    t.string "country"
    t.datetime "created_at", null: false
    t.string "device_type"
    t.string "ip_address"
    t.float "latitude"
    t.float "longitude"
    t.string "method"
    t.string "os"
    t.string "path", null: false
    t.text "referrer"
    t.string "session_id"
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.integer "user_id"
    t.index ["country"], name: "index_page_views_on_country"
    t.index ["created_at", "path"], name: "index_page_views_on_created_at_and_path"
    t.index ["created_at"], name: "index_page_views_on_created_at"
    t.index ["path"], name: "index_page_views_on_path"
    t.index ["session_id"], name: "index_page_views_on_session_id"
    t.index ["user_id"], name: "index_page_views_on_user_id"
  end

  create_table "posts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "published"
    t.datetime "published_at"
    t.string "slug"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_posts_on_user_id"
  end

  create_table "revenue_entries", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.text "note"
    t.date "received_on", null: false
    t.string "source", null: false
    t.integer "tax_year", null: false
    t.datetime "updated_at", null: false
    t.index ["tax_year"], name: "index_revenue_entries_on_tax_year"
  end

  create_table "saved_jobs", force: :cascade do |t|
    t.datetime "applied_at"
    t.datetime "created_at", null: false
    t.integer "job_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["job_id"], name: "index_saved_jobs_on_job_id"
    t.index ["user_id", "job_id"], name: "index_saved_jobs_on_user_id_and_job_id", unique: true
    t.index ["user_id"], name: "index_saved_jobs_on_user_id"
  end

  create_table "scraper_sources", force: :cascade do |t|
    t.string "api_key_name"
    t.json "config", default: {}
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "last_run_at"
    t.text "last_run_error"
    t.integer "last_run_jobs_found", default: 0
    t.string "last_run_status"
    t.string "name", null: false
    t.string "schedule", default: "every_6h", null: false
    t.json "search_terms", default: []
    t.string "slug", null: false
    t.string "source_url"
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_scraper_sources_on_enabled"
    t.index ["slug"], name: "index_scraper_sources_on_slug", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "impersonated_user_id"
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["impersonated_user_id"], name: "index_sessions_on_impersonated_user_id"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "smoke_test_runs", force: :cascade do |t|
    t.text "console_errors"
    t.decimal "cost_dollars", precision: 10, scale: 6, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.datetime "ended_at"
    t.text "error_message"
    t.string "name", null: false
    t.datetime "started_at", null: false
    t.string "status", null: false
    t.text "summary"
    t.datetime "updated_at", null: false
    t.index ["name", "started_at"], name: "index_smoke_test_runs_on_name_and_started_at"
    t.index ["started_at"], name: "index_smoke_test_runs_on_started_at"
  end

  create_table "social_accounts", force: :cascade do |t|
    t.text "access_token"
    t.string "avatar_url"
    t.integer "connected_by_id"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "external_id"
    t.string "handle"
    t.datetime "last_synced_at"
    t.text "metadata"
    t.string "platform", null: false
    t.text "refresh_token"
    t.text "scopes"
    t.string "status", default: "active", null: false
    t.datetime "token_expires_at"
    t.text "token_secret"
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["connected_by_id"], name: "index_social_accounts_on_connected_by_id"
    t.index ["status"], name: "index_social_accounts_on_status"
    t.index ["workspace_id", "platform", "external_id"], name: "idx_social_accts_on_ws_platform_extid", unique: true
    t.index ["workspace_id"], name: "index_social_accounts_on_workspace_id"
  end

  create_table "social_leads", force: :cascade do |t|
    t.string "author"
    t.datetime "created_at", null: false
    t.text "draft_reply"
    t.string "external_id", null: false
    t.string "matched_query"
    t.string "platform", null: false
    t.datetime "posted_at"
    t.string "reason"
    t.integer "score", default: 0, null: false
    t.string "status", default: "new", null: false
    t.text "text", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.integer "workspace_id", null: false
    t.index ["workspace_id", "platform", "external_id"], name: "index_social_leads_on_ws_platform_external", unique: true
    t.index ["workspace_id", "status"], name: "index_social_leads_on_workspace_id_and_status"
    t.index ["workspace_id"], name: "index_social_leads_on_workspace_id"
  end

  create_table "social_post_logs", force: :cascade do |t|
    t.datetime "copied_at"
    t.datetime "created_at", null: false
    t.text "enhanced_text"
    t.string "event_url"
    t.datetime "posted_at"
    t.datetime "updated_at", null: false
    t.string "x_approval_token"
    t.datetime "x_deleted_at"
    t.text "x_draft_text"
    t.datetime "x_drafted_at"
    t.string "x_post_id"
    t.datetime "x_posted_at"
    t.datetime "x_skipped_at"
    t.index ["event_url"], name: "index_social_post_logs_on_event_url", unique: true
    t.index ["x_approval_token"], name: "index_social_post_logs_on_x_approval_token"
  end

  create_table "subscribers", force: :cascade do |t|
    t.boolean "confirmed", default: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_subscribers_on_email", unique: true
    t.index ["token"], name: "index_subscribers_on_token", unique: true
  end

  create_table "tracked_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.integer "workspace_id"
    t.index ["token"], name: "index_tracked_links_on_token", unique: true
    t.index ["workspace_id"], name: "index_tracked_links_on_workspace_id"
  end

  create_table "usage_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.text "metadata"
    t.integer "quantity", default: 1, null: false
    t.integer "unit_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.integer "workspace_id", null: false
    t.index ["kind"], name: "index_usage_events_on_kind"
    t.index ["user_id"], name: "index_usage_events_on_user_id"
    t.index ["workspace_id", "created_at"], name: "index_usage_events_on_workspace_id_and_created_at"
    t.index ["workspace_id"], name: "index_usage_events_on_workspace_id"
  end

  create_table "users", force: :cascade do |t|
    t.integer "ai_enhances_used", default: 0, null: false
    t.boolean "android_push_enabled", default: true, null: false
    t.string "anthropic_api_key"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email_address"
    t.string "email_verification_token"
    t.datetime "email_verified_at"
    t.boolean "ios_push_enabled", default: true, null: false
    t.string "npub"
    t.string "password_digest"
    t.string "pubkey_hex"
    t.string "role", default: "user"
    t.boolean "social_push_enabled", default: true, null: false
    t.datetime "updated_at", null: false
    t.string "webauthn_id"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["email_verification_token"], name: "index_users_on_email_verification_token", unique: true
    t.index ["npub"], name: "index_users_on_npub", unique: true
    t.index ["pubkey_hex"], name: "index_users_on_pubkey_hex", unique: true
    t.index ["webauthn_id"], name: "index_users_on_webauthn_id", unique: true
  end

  create_table "videos", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "position"
    t.boolean "published"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "youtube_id"
  end

  create_table "workspace_agents", force: :cascade do |t|
    t.integer "agent_number", null: false
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "kind", null: false
    t.json "settings", default: {}, null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["workspace_id", "agent_number"], name: "index_workspace_agents_on_workspace_id_and_agent_number", unique: true
    t.index ["workspace_id", "kind"], name: "index_workspace_agents_on_workspace_id_and_kind", unique: true
    t.index ["workspace_id"], name: "index_workspace_agents_on_workspace_id"
  end

  create_table "workspace_drafts", force: :cascade do |t|
    t.integer "author_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.text "error"
    t.string "image_url"
    t.boolean "link_card", default: false, null: false
    t.datetime "published_at"
    t.text "results"
    t.datetime "scheduled_for"
    t.string "source_url"
    t.string "status", default: "draft", null: false
    t.text "target_platforms", default: "[]", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["author_id"], name: "index_workspace_drafts_on_author_id"
    t.index ["scheduled_for"], name: "index_workspace_drafts_on_scheduled_for"
    t.index ["status"], name: "index_workspace_drafts_on_status"
    t.index ["workspace_id", "created_at"], name: "index_workspace_drafts_on_workspace_id_and_created_at"
    t.index ["workspace_id", "source_url"], name: "index_workspace_drafts_on_workspace_id_and_source_url"
    t.index ["workspace_id"], name: "index_workspace_drafts_on_workspace_id"
  end

  create_table "workspace_invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.integer "accepted_by_id"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.integer "invited_by_id", null: false
    t.datetime "revoked_at"
    t.string "role", default: "editor", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["accepted_by_id"], name: "index_workspace_invitations_on_accepted_by_id"
    t.index ["expires_at"], name: "index_workspace_invitations_on_expires_at"
    t.index ["invited_by_id"], name: "index_workspace_invitations_on_invited_by_id"
    t.index ["token"], name: "index_workspace_invitations_on_token", unique: true
    t.index ["workspace_id", "email"], name: "index_workspace_invitations_on_workspace_id_and_email"
    t.index ["workspace_id"], name: "index_workspace_invitations_on_workspace_id"
  end

  create_table "workspace_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "daily_digest_enabled", default: true, null: false
    t.datetime "last_active_at"
    t.boolean "push_enabled", default: true, null: false
    t.string "role", default: "editor", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "workspace_id", null: false
    t.index ["role"], name: "index_workspace_memberships_on_role"
    t.index ["user_id"], name: "index_workspace_memberships_on_user_id"
    t.index ["workspace_id", "user_id"], name: "index_workspace_memberships_on_workspace_id_and_user_id", unique: true
    t.index ["workspace_id"], name: "index_workspace_memberships_on_workspace_id"
  end

  create_table "workspace_posts", force: :cascade do |t|
    t.integer "author_id", null: false
    t.text "body", null: false
    t.integer "bookmarks", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "error"
    t.string "image_url"
    t.integer "impressions", default: 0, null: false
    t.integer "likes", default: 0, null: false
    t.datetime "metrics_synced_at"
    t.string "platform", null: false
    t.datetime "posted_at"
    t.integer "quotes", default: 0, null: false
    t.string "remote_id"
    t.string "remote_url"
    t.integer "replies", default: 0, null: false
    t.integer "reposts", default: 0, null: false
    t.integer "social_account_id"
    t.string "source_url"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["author_id"], name: "index_workspace_posts_on_author_id"
    t.index ["metrics_synced_at"], name: "index_workspace_posts_on_metrics_synced_at"
    t.index ["social_account_id"], name: "index_workspace_posts_on_social_account_id"
    t.index ["status"], name: "index_workspace_posts_on_status"
    t.index ["workspace_id", "created_at"], name: "index_workspace_posts_on_workspace_id_and_created_at"
    t.index ["workspace_id", "source_url"], name: "index_workspace_posts_on_workspace_id_and_source_url"
    t.index ["workspace_id"], name: "index_workspace_posts_on_workspace_id"
  end

  create_table "workspaces", force: :cascade do |t|
    t.datetime "archived_at"
    t.decimal "base_fee_dollars", precision: 10, scale: 2
    t.boolean "base_fee_waived", default: false, null: false
    t.boolean "billing_enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.decimal "discount_percent", precision: 5, scale: 2, default: "0.0"
    t.integer "flyer_unit_cents"
    t.string "name", null: false
    t.integer "owner_id", null: false
    t.boolean "pricing_visible_to_members", default: false, null: false
    t.text "settings"
    t.boolean "show_grocery_prices", default: false, null: false
    t.string "slug", null: false
    t.string "source_url"
    t.decimal "test_cost_per_minute", precision: 12, scale: 6
    t.string "timezone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.decimal "usage_multiplier", precision: 6, scale: 2, default: "1.0", null: false
    t.index ["archived_at"], name: "index_workspaces_on_archived_at"
    t.index ["owner_id"], name: "index_workspaces_on_owner_id"
    t.index ["slug"], name: "index_workspaces_on_slug", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_memories", "agents"
  add_foreign_key "ai_call_logs", "users"
  add_foreign_key "apply_requests", "jobs"
  add_foreign_key "connect_chat_messages", "users"
  add_foreign_key "connect_chat_messages", "workspaces"
  add_foreign_key "credentials", "users"
  add_foreign_key "device_tokens", "users"
  add_foreign_key "fleet_requests", "users"
  add_foreign_key "grocery_receipts", "users", column: "created_by_id"
  add_foreign_key "hidden_jobs", "jobs"
  add_foreign_key "hidden_jobs", "users"
  add_foreign_key "impersonation_logs", "users", column: "actor_id"
  add_foreign_key "impersonation_logs", "users", column: "target_id"
  add_foreign_key "ingredient_prices", "grocery_receipts"
  add_foreign_key "inventory_captures", "users", on_delete: :nullify
  add_foreign_key "inventory_movements", "inventory_items", on_delete: :cascade
  add_foreign_key "inventory_movements", "users", on_delete: :nullify
  add_foreign_key "invoices", "workspaces"
  add_foreign_key "job_matches", "jobs", on_delete: :cascade
  add_foreign_key "job_sources", "jobs"
  add_foreign_key "kitchen_events", "kitchen_snapshots"
  add_foreign_key "kitchen_manual_classes", "users", column: "created_by_id"
  add_foreign_key "kitchen_packet_links", "kitchen_packets"
  add_foreign_key "kitchen_ticket_digests", "kitchen_snapshots"
  add_foreign_key "link_scans", "tracked_links"
  add_foreign_key "notifications", "users"
  add_foreign_key "page_views", "users"
  add_foreign_key "posts", "users"
  add_foreign_key "saved_jobs", "jobs"
  add_foreign_key "saved_jobs", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "sessions", "users", column: "impersonated_user_id"
  add_foreign_key "social_accounts", "users", column: "connected_by_id"
  add_foreign_key "social_accounts", "workspaces"
  add_foreign_key "social_leads", "workspaces"
  add_foreign_key "tracked_links", "workspaces"
  add_foreign_key "usage_events", "workspaces"
  add_foreign_key "workspace_agents", "workspaces"
  add_foreign_key "workspace_drafts", "users", column: "author_id"
  add_foreign_key "workspace_drafts", "workspaces"
  add_foreign_key "workspace_invitations", "users", column: "accepted_by_id"
  add_foreign_key "workspace_invitations", "users", column: "invited_by_id"
  add_foreign_key "workspace_invitations", "workspaces"
  add_foreign_key "workspace_memberships", "users"
  add_foreign_key "workspace_memberships", "workspaces"
  add_foreign_key "workspace_posts", "social_accounts"
  add_foreign_key "workspace_posts", "users", column: "author_id"
  add_foreign_key "workspace_posts", "workspaces"
  add_foreign_key "workspaces", "users", column: "owner_id"
end
