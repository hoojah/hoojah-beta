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

ActiveRecord::Schema[8.1].define(version: 2026_08_05_032330) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "flags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "hujah_id", null: false
    t.integer "subject"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["hujah_id"], name: "index_flags_on_hujah_id"
    t.index ["user_id"], name: "index_flags_on_user_id"
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

  add_foreign_key "flags", "hujahs"
  add_foreign_key "flags", "users"
  add_foreign_key "hujahs", "users"
  add_foreign_key "notifications", "users"
  add_foreign_key "votes", "users"
end
