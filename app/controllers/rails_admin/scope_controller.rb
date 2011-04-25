module RailsAdmin
  class ScopeController < RailsAdmin::ApplicationController
    def set_scope
      session[:scope] = {}
      model = RailsAdmin::Config::Scope.models[RailsAdmin::Config::Scope.models.index { |model| params[:model] == model.name }]
      session[:scope][model.name] = params[:selected]
      get_scope_models
      respond_to do |format|
        format.js {render :partial => 'scope_selector', :locals => {:models => RailsAdmin::Config::Scope.models}}
      end
    end
  end
end