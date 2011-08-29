class CreateApplicationsAdminRoles < ActiveRecord::Migration
  def self.up
    create_table :applications_admin_roles, :id => false do |t|
      t.references :application, :admin_role
      t.timestamps
    end
  end

  def self.down
    drop_table :applications_admin_roles
  end
end
