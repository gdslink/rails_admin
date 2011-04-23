module RailsAdmin
  class ScopeController < RailsAdmin::ApplicationController
    def set_scope
      session[:scope] = {}
      RailsAdmin::Config::Scope.models.each do |model|
        session[:scope][model.name] = params[:selected] if params[:model] == model.name
      end
      get_scope_models
      render :nothing => true
    end
  end
end