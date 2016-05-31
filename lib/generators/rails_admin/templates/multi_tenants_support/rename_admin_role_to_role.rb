class RenameAdminRoleToRole < ActiveRecord::Migration
  def change
    rename_table :admin_roles, :roles
    rename_column :admin_roles_admin_permissions, :admin_role_id, :role_id
    rename_table :admin_roles_admin_permissions, :roles_admin_permissions
    rename_column :users_admin_roles, :admin_role_id, :role_id
    rename_table :users_admin_roles, :users_roles
  end
end