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

ActiveRecord::Schema[8.1].define(version: 2026_08_05_140002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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

  create_table "debates", force: :cascade do |t|
    t.bigint "challenger_id", null: false
    t.integer "challenger_stance", null: false
    t.datetime "created_at", null: false
    t.bigint "hujah_id", null: false
    t.bigint "opponent_id", null: false
    t.integer "opponent_stance", null: false
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
    t.integer "subject"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["hujah_id"], name: "index_flags_on_hujah_id"
    t.index ["user_id"], name: "index_flags_on_user_id"
  end

  create_table "follows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "followed_id", null: false
    t.bigint "follower_id", null: false
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

  create_table "hujahs", force: :cascade do |t|
    t.integer "agree_count", default: 0
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "disagree_count", default: 0
    t.integer "neutral_count", default: 0
    t.integer "parent_id"
    t.string "slug"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
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

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: ""
    t.string "encrypted_password", default: "", null: false
    t.string "full_name"
    t.string "headline", default: ""
    t.string "link", default: ""
    t.string "location", default: ""
    t.string "photo", default: ""
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "hujah_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "vote", null: false, array: true
    t.index ["user_id"], name: "index_votes_on_user_id"
  end

  add_foreign_key "debate_turns", "debates"
  add_foreign_key "debate_turns", "users"
  add_foreign_key "debates", "hujahs"
  add_foreign_key "debates", "users", column: "challenger_id"
  add_foreign_key "debates", "users", column: "opponent_id"
  add_foreign_key "flags", "hujahs"
  add_foreign_key "flags", "users"
  add_foreign_key "follows", "users", column: "followed_id"
  add_foreign_key "follows", "users", column: "follower_id"
  add_foreign_key "hujahs", "users"
  add_foreign_key "notifications", "users"
  add_foreign_key "votes", "users"
end
