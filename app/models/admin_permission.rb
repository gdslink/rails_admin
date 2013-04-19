class AdminPermission < ActiveRecord::Base
  has_and_belongs_to_many :roles, :join_table => :roles_admin_permissions

  after_find :translate

  def translate
    if self.action == 'see_history'
      self.name = I18n.t("permissions.read") + " " + I18n.t("permissions.history")
    elsif self.subject_class == 'Ckeditor::Asset'
      self.name = I18n.t("permissions.#{self.action}") + " " + I18n.t("permissions.resources")
    else
      self.name = I18n.t("permissions.#{self.action}") + " " + self.subject_class.constantize.model_name.human
    end
  end

end
