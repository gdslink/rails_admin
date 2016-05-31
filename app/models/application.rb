class Application < ActiveRecord::Base
  belongs_to :company

  validates_presence_of   :company_id
  validates_presence_of   :name
  validates_uniqueness_of :name, :scope => :company_id  

  validates_format_of :key, :with => /\A\w[\w\.+\-_]+$/, :message => I18n.t("edit.errors.invalid_name_alpha_only")
end
