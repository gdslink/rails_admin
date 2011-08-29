class User < ActiveRecord::Base
  belongs_to :company
  has_and_belongs_to_many :admin_roles, :join_table => :users_admin_roles
  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable, :lockable and :timeoutable
  devise :database_authenticatable,
         :recoverable, :rememberable, :trackable, :validatable

  # Setup accessible (or protected) attributes for your model
  attr_accessible :email, :password, :password_confirmation, :remember_me

  def is?(admin_role)
    admin_roles.map{|r| r.name.downcase}.include?(admin_role.to_s)
  end

end
