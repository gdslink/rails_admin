class DropApplicationsAdminRoles < ActiveRecord::Migration
  def change
  	drop_table :applications_admin_roles
  end
end