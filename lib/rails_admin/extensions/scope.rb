require 'rails_admin/extensions/scope/scope_adapter'
require 'rails_admin/extensions/scope/active_record_current_scope'

RailsAdmin.add_extension(:scope, RailsAdmin::Extensions::Scope, { scope: true})
