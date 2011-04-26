require 'rails_admin/extensions/scope/scope_adapter'

RailsAdmin.add_extension(:scope, RailsAdmin::Extensions::Scope, {
  :scope => true
})
