class Permission < ActiveRecord::Base
  has_and_belongs_to_many :roles, :join_table => :roles_permissions

  # rails_admin do
  #   edit do
  #     field :name
  #     field :description
  #     group :permissions do
  #       label "Permissions"
  #       field
  #     end          
  #   end
  # end  

end
