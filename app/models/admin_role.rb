class AdminRole < ActiveRecord::Base
  has_and_belongs_to_many :admin_permissions, :join_table => :admin_roles_admin_permissions
  has_and_belongs_to_many :applications, :join_table => :applications_admin_roles
  has_and_belongs_to_many :users, :join_table => :users_roles  

  rails_admin do
    edit do
      field :name
      field :description
      group :permissions do        
        label "Permissions"
        field :applications
        field :admin_permissions do
          label "Permissions"
        end
      end          
    end
  end  
end