# Solid Cable's schema as a migration. See the long comment in
# db/cache_migrate/20260822000001_create_solid_cache_tables.rb for why these three
# directories exist — `db:prepare` skips a config's schema dump once `schema_migrations`
# exists in the target database, which after the Slice 10b collapse onto one Postgres is
# always true for cache/queue/cable.
#
# Losing this table is not a degraded-but-working state: Action Cable is how a debate
# turn reaches the other participant, so without `solid_cable_messages` every
# `Turbo::StreamsChannel` broadcast raises.
#
# Equivalent to db/cable_schema.rb minus `force: :cascade` (a dump artifact).
class CreateSolidCableTables < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_cable_messages do |t|
      t.binary :channel, limit: 1024, null: false
      t.binary :payload, limit: 536870912, null: false
      t.datetime :created_at, null: false
      t.integer :channel_hash, limit: 8, null: false

      t.index [:channel], name: "index_solid_cable_messages_on_channel"
      t.index [:channel_hash], name: "index_solid_cable_messages_on_channel_hash"
      t.index [:created_at], name: "index_solid_cable_messages_on_created_at"
    end
  end
end
