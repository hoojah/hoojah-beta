class AddFavouritedAtToHujahs < ActiveRecord::Migration[8.1]
  # Nullable, no default: a metadata-only add on Postgres, safe under strong_migrations
  # on the populated hujahs table. Set on a REPLY when the parent claim's author
  # favourites it (Hujah#favourite!); nil means not favourited.
  def change
    add_column :hujahs, :favourited_at, :datetime
  end
end
