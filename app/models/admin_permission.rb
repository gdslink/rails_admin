class AdminPermission < ActiveRecord::Base
  has_and_belongs_to_many :admin_roles, :join_table => :admin_roles_admin_permissions
  
end
