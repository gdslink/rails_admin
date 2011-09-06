class AddRoleBelongsToApplication < ActiveRecord::Migration
  def change
    add_column :roles, :application_id,  :integer
  end
end
