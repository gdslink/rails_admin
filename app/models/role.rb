class Role < ActiveRecord::Base
  has_and_belongs_to_many :permissions, :join_table => :roles_permissions
  has_and_belongs_to_many :users, :join_table => :users_roles

  rails_admin do
    edit do
      field :name
      field :description
      group :permissions do
        label "Permissions"
        field :permissions
      end          
    end
  end  
end