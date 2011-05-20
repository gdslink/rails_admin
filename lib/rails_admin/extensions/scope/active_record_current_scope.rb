module RailsAdmin

  # This module adds the default_scope class method to a model. It is included in the model adapters.
  module DefaultScope
    module ClassMethods
      # Returns a scope which fetches only the records that the passed ability
      # can perform a given action on. The action defaults to :index. This
      # is usually called from a controller and passed the +current_ability+.
      #
      #   @articles = Article.accessible_by(current_ability)
      #
      # Here only the articles which the user is able to read will be returned.
      # If the user does not have permission to read any articles then an empty
      # result is returned. Since this is a scope it can be combined with any
      # other scopes or pagination.
      #
      # An alternative action can optionally be passed as a second argument.
      #
      #   @articles = Article.accessible_by(current_ability, :update)
      #
      # Here only the articles which the user can update are returned.
      def current_scope(authorization_adapter, scope_adapter)
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
  include RailsAdmin::DefaultScope
end