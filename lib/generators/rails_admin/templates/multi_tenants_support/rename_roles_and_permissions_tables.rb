class RenameRolesAndPermissionsTables < ActiveRecord::Migration
  def self.up
    rename_table :roles, :admin_roles
    rename_table :permissions, :admin_permissions
    rename_column :roles_permissions, :role_id, :admin_role_id
    rename_column :roles_permissions, :permission_id, :admin_permission_id
    rename_table :roles_permissions, :admin_roles_admin_permissions
    rename_column :users_roles, :role_id, :admin_role_id
    rename_table :users_roles, :users_admin_roles    
  end
 
  def self.down
    rename_table :admin_roles, :roles
    rename_table :admin_permissions, :permissions
    rename_column :admin_roles_admin_permissions, :admin_role_id, :role_id
    rename_column :admin_roles_admin_permissions, :admin_permission_id, :permission_id
    rename_table :admin_roles_admin_permissions, :roles_permissions
    rename_column :users_admin_roles, :admin_role_id, :role_id
    rename_table :users_admin_roles, :users_roles        
  end
end