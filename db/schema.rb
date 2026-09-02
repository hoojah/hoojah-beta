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

ActiveRecord::Schema[8.1].define(version: 2026_09_02_081244) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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

  create_table "blocks", force: :cascade do |t|
    t.bigint "blocked_id", null: false
    t.bigint "blocker_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blocked_id"], name: "index_blocks_on_blocked_id"
    t.index ["blocker_id", "blocked_id"], name: "index_blocks_on_blocker_id_and_blocked_id", unique: true
    t.index ["blocker_id"], name: "index_blocks_on_blocker_id"
    t.check_constraint "blocker_id <> blocked_id", name: "no_self_block"
  end

  create_table "debate_turns", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.bigint "debate_id", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["debate_id", "position"], name: "index_debate_turns_on_debate_id_and_position", unique: true
    t.index ["debate_id"], name: "index_debate_turns_on_debate_id"
    t.index ["user_id"], name: "index_debate_turns_on_user_id"
  end

  create_table "debate_verdicts", force: :cascade do |t|
    t.integer "choice", null: false
    t.datetime "created_at", null: false
    t.bigint "debate_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["debate_id", "user_id"], name: "index_debate_verdicts_on_debate_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_debate_verdicts_on_user_id"
  end

  create_table "debates", force: :cascade do |t|
    t.bigint "challenger_id", null: false
    t.integer "challenger_stance", null: false
    t.datetime "created_at", null: false
    t.bigint "hujah_id", null: false
    t.text "opening_argument"
    t.bigint "opponent_id", null: false
    t.integer "opponent_stance", null: false
    t.integer "rounds_limit", default: 4, null: false
    t.string "slug", null: false
    t.integer "status", null: false
    t.datetime "updated_at", null: false
    t.index ["challenger_id"], name: "index_debates_on_challenger_id"
    t.index ["hujah_id", "challenger_id", "opponent_id"], name: "no_dup_live_debate", unique: true, where: "(status = ANY (ARRAY[0, 1]))"
    t.index ["hujah_id"], name: "index_debates_on_hujah_id"
    t.index ["opponent_id"], name: "index_debates_on_opponent_id"
    t.index ["slug"], name: "index_debates_on_slug", unique: true
  end

  create_table "flags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "hujah_id", null: false
    t.datetime "resolved_at"
    t.bigint "resolved_by_id"
    t.integer "status", default: 0, null: false
    t.integer "subject"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["hujah_id"], name: "index_flags_on_hujah_id"
    t.index ["user_id", "hujah_id"], name: "index_flags_on_user_and_hujah", unique: true
    t.index ["user_id"], name: "index_flags_on_user_id"
  end

  create_table "follows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "followed_id", null: false
    t.bigint "follower_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["followed_id"], name: "index_follows_on_followed_id"
    t.index ["follower_id", "followed_id"], name: "index_follows_on_follower_id_and_followed_id", unique: true
    t.index ["follower_id"], name: "index_follows_on_follower_id"
    t.check_constraint "follower_id <> followed_id", name: "no_self_follow"
  end

  create_table "friendly_id_slugs", force: :cascade do |t|
    t.datetime "created_at"
    t.string "scope"
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_type", "sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_type_and_sluggable_id"
  end

  create_table "hashtag_hujahs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "hashtag_id", null: false
    t.bigint "hujah_id", null: false
    t.datetime "updated_at", null: false
    t.index ["hashtag_id", "hujah_id"], name: "index_hashtag_hujahs_on_hashtag_id_and_hujah_id", unique: true
    t.index ["hashtag_id"], name: "index_hashtag_hujahs_on_hashtag_id"
    t.index ["hujah_id"], name: "index_hashtag_hujahs_on_hujah_id"
  end

  create_table "hashtags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display", null: false
    t.integer "hujahs_count", default: 0, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_hashtags_on_name", unique: true
  end

  create_table "hujahs", force: :cascade do |t|
    t.integer "agree_count", default: 0
    t.string "agree_label"
    t.boolean "allow_debates", default: true, null: false
    t.text "body", null: false
    t.datetime "body_edited_at"
    t.integer "conviction_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "disagree_count", default: 0
    t.string "disagree_label"
    t.integer "moderation_status", default: 0, null: false
    t.integer "neutral_count", default: 0
    t.string "neutral_label"
    t.integer "parent_id"
    t.string "slug"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "visibility", default: 0, null: false
    t.integer "vote"
    t.index ["slug"], name: "index_hujahs_on_slug", unique: true
    t.index ["user_id"], name: "index_hujahs_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.string "body"
    t.integer "category", null: false
    t.datetime "created_at", null: false
    t.bigint "debate_id"
    t.integer "hujah_id"
    t.boolean "read", default: false
    t.integer "subject_user_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "short_links", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "target_path", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_short_links_on_code", unique: true
    t.index ["target_path"], name: "index_short_links_on_target_path", unique: true
  end

  create_table "user_badges", force: :cascade do |t|
    t.string "badge_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "badge_key"], name: "index_user_badges_on_user_id_and_badge_key", unique: true
    t.index ["user_id"], name: "index_user_badges_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: ""
    t.boolean "email_notifications", default: true, null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "followers_count", default: 0, null: false
    t.integer "following_count", default: 0, null: false
    t.string "full_name"
    t.string "headline", default: ""
    t.string "link", default: ""
    t.string "location", default: ""
    t.string "photo", default: ""
    t.boolean "private", default: false, null: false
    t.string "provider"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", default: 0, null: false
    t.string "uid"
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["private"], name: "index_users_on_private"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "votes", force: :cascade do |t|
    t.boolean "conviction", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "hujah_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "vote", null: false, array: true
    t.index ["user_id"], name: "index_votes_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "blocks", "users", column: "blocked_id"
  add_foreign_key "blocks", "users", column: "blocker_id"
  add_foreign_key "debate_turns", "debates"
  add_foreign_key "debate_turns", "users"
  add_foreign_key "debate_verdicts", "debates"
  add_foreign_key "debate_verdicts", "users"
  add_foreign_key "debates", "hujahs"
  add_foreign_key "debates", "users", column: "challenger_id"
  add_foreign_key "debates", "users", column: "opponent_id"
  add_foreign_key "flags", "hujahs"
  add_foreign_key "flags", "users"
  add_foreign_key "flags", "users", column: "resolved_by_id"
  add_foreign_key "follows", "users", column: "followed_id"
  add_foreign_key "follows", "users", column: "follower_id"
  add_foreign_key "hashtag_hujahs", "hashtags"
  add_foreign_key "hashtag_hujahs", "hujahs"
  add_foreign_key "hujahs", "users"
  add_foreign_key "notifications", "users"
  add_foreign_key "user_badges", "users"
  add_foreign_key "votes", "users"
end
