class Company < ActiveRecord::Base
  image_accessor :logo_image
  has_many :users

  validates_presence_of   :name
  validates_uniqueness_of :name

  validates_format_of :key, :with => /\A\w[\w\.+\-_]+$/, :message => I18n.t("edit.errors.invalid_name_alpha_only")
end
