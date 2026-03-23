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

ActiveRecord::Schema[8.1].define(version: 2026_03_23_185859) do
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

  create_table "hidden_jobs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "job_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["job_id"], name: "index_hidden_jobs_on_job_id"
    t.index ["user_id", "job_id"], name: "index_hidden_jobs_on_user_id_and_job_id", unique: true
    t.index ["user_id"], name: "index_hidden_jobs_on_user_id"
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
    t.string "salary"
    t.string "source"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["category"], name: "index_jobs_on_category"
    t.index ["normalized_company", "normalized_title"], name: "index_jobs_on_normalized_company_and_normalized_title"
    t.index ["posted_at"], name: "index_jobs_on_posted_at"
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

  create_table "page_views", force: :cascade do |t|
    t.string "browser"
    t.string "city"
    t.string "country"
    t.datetime "created_at", null: false
    t.string "device_type"
    t.string "ip_address"
    t.float "latitude"
    t.float "longitude"
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

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
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

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email_address"
    t.string "email_verification_token"
    t.datetime "email_verified_at"
    t.string "npub"
    t.string "password_digest"
    t.string "pubkey_hex"
    t.string "role", default: "member"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["email_verification_token"], name: "index_users_on_email_verification_token", unique: true
    t.index ["npub"], name: "index_users_on_npub", unique: true
    t.index ["pubkey_hex"], name: "index_users_on_pubkey_hex", unique: true
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

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "hidden_jobs", "jobs"
  add_foreign_key "hidden_jobs", "users"
  add_foreign_key "job_sources", "jobs"
  add_foreign_key "page_views", "users"
  add_foreign_key "posts", "users"
  add_foreign_key "saved_jobs", "jobs"
  add_foreign_key "saved_jobs", "users"
  add_foreign_key "sessions", "users"
end
