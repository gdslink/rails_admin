module RailsAdmin

  # This module adds the default_scope class method to a model. It is included in the model adapters.
  module CurrentScope
    module ClassMethods
      # Returns a scope which fetches only the records that the passed ability
      # can perform a given action on. 
      # authorization_adapter and scope_adapter are instance variables set at the controller level.
      def limit_scope(authorization_adapter, scope_adapter)
        abstract_model = RailsAdmin::AbstractModel.new(self.name)
        scope = authorization_adapter && authorization_adapter.query(:read, abstract_model)
        scope = scope_adapter.apply_scope(scope, abstract_model) if scope_adapter
      end
    end

    def self.included(base)
      base.extend ClassMethods
    end
  end
end

ActiveRecord::Base.class_eval do
  include RailsAdmin::CurrentScope
end