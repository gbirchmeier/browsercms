class Browsercms305 < ActiveRecord::Migration
  def self.up
    add_column :cms_users, :reset_token, :string
  end

  def self.down
    remove_column :cms_users, :reset_token
  end
end
