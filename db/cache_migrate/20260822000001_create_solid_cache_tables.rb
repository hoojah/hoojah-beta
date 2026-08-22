# Solid Cache's schema, as a MIGRATION rather than the `db/cache_schema.rb` dump the
# gem's installer leaves behind. Slice 10b.
#
# Why this directory exists at all — the trap it defuses:
#
# `config/database.yml` production points primary/cache/queue/cable at ONE Postgres
# (see the comment there). `db:prepare` decides whether to load a config's schema dump
# with `ActiveRecord::Tasks::DatabaseTasks#initialize_database`, which asks
# `schema_migration.table_exists?`. On a collapsed layout the primary has already
# created `schema_migrations` in that database by the time the `cache` config is
# reached, so `database_already_initialized` is true, `db/cache_schema.rb` is never
# loaded, and the app deploys with NO `solid_cache_entries` table — a green deploy that
# 500s on the first cache write. Same for queue and cable.
#
# Migrations are checked per-version, not per-database, so they survive the collapse:
# the version below is simply absent from the shared `schema_migrations` table and
# `db:migrate` runs it. This also means every future solid_cache upgrade migration
# lands here and is applied by the ordinary release command, with no bespoke step.
#
# Kept byte-for-byte equivalent to db/cache_schema.rb (minus `force: :cascade`, which is
# a schema-dump artifact and would DROP a populated table on re-run). That file is left
# in place as the upstream reference and as the split-back-out path.
class CreateSolidCacheTables < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_cache_entries do |t|
      t.binary :key, limit: 1024, null: false
      t.binary :value, limit: 536870912, null: false
      t.datetime :created_at, null: false
      t.integer :key_hash, limit: 8, null: false
      t.integer :byte_size, limit: 4, null: false

      t.index [:byte_size], name: "index_solid_cache_entries_on_byte_size"
      t.index [:key_hash, :byte_size], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
      t.index [:key_hash], name: "index_solid_cache_entries_on_key_hash", unique: true
    end
  end
end
