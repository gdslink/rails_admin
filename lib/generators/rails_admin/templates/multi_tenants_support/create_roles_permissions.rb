class CreateRolesPermissions < ActiveRecord::Migration
  def self.up
    create_table :roles_permissions, :id => false do |t|
      t.references :role, :permission
      t.timestamps
    end
  end

  def self.down
    drop_table :roles_permissions
  end
end
