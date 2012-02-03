class Company < ActiveRecord::Base
  has_attached_file :logo_image, :styles => {thumb => "60x30#"}
  attr_accessor :delete_logo_image
  before_validation { self.logo_image.clear if self.delete_logo_image == '1' }

  has_many :users

  validates_presence_of   :name
  validates_uniqueness_of :name

  validates_format_of :key, :with => /\A\w[\w\.+\-_]+$/, :message => I18n.t("edit.errors.invalid_name_alpha_only")
end
