class User < ActiveRecord::Base
  belongs_to :company
  has_and_belongs_to_many :roles, :join_table => :users_roles
  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable, :lockable and :timeoutable
  devise :database_authenticatable,
         :recoverable, :rememberable, :trackable, :validatable

  # Setup accessible (or protected) attributes for your model
  attr_accessible :email, :password, :password_confirmation, :remember_me

  def is_root?
    self.is_root
  end

  rails_admin do
    edit do
      field :email
      field :password
      field :password_confirmation

      group :roles do        
        field :is_root do
          label "Enable root"
          visible do
            bindings[:view].current_user.is_root? if bindings and bindings.include?(:view)
          end
        end

        field :roles
      end
    end
  end

end
