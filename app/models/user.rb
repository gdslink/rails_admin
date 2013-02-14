class User < ActiveRecord::Base
  belongs_to :company
  has_and_belongs_to_many :roles, :join_table => :users_roles
  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable, :lockable and :timeoutable
  devise :database_authenticatable,
         :recoverable, :rememberable, :trackable, :validatable, :token_authenticatable, :lockable, :omniauthable

  # Setup accessible (or protected) attributes for your model
  attr_accessible :email, :password, :password_confirmation, :remember_me, :company_id, :authentication_token

  before_save :reset_roles

  def reset_roles
    self.roles = self.roles.reject{|r| r.application.company != self.company}
  end

  def is_root?
    self.is_root
  end

  rails_admin do
    edit do
      field :email
      field :password
      field :password_confirmation
      field :company
      group :roles do        
        field :is_root do
          label "Root user"
          help "Allow user to administer any company and any application."
          visible do
            bindings[:view].current_user.is_root? if bindings and bindings.include?(:view)
          end
        end
        field :is_admin do
          label "Admin User"
          help "Allow user to administer any application under the company he belongs to."
          visible do
            bindings[:view].current_user.is_root? or bindings[:view].current_user.is_admin? if bindings and bindings.include?(:view)
          end
        end        
        field :roles
      end
    end
  end

end
