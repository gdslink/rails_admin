require 'rails_admin/abstract_model'

module RailsAdmin
  class ApplicationController < ::ApplicationController
    newrelic_ignore if defined?(NewRelic)

    before_filter :_authenticate!
    before_filter :_authorize!
    before_filter :_scope!    
    before_filter :set_plugin_name
    before_filter :_get_scope_models!
    before_filter :_get_scope_parameters!
    
    helper_method :_current_user

    def get_model
      model_name = to_model_name(params[:model_name])
      @abstract_model = RailsAdmin::AbstractModel.new(model_name)
      @model_config = RailsAdmin.config(@abstract_model)
      not_found if @model_config.excluded?
      @properties = @abstract_model.properties
    end

    def to_model_name(param)
      parts = param.split("~")
      parts.map{|x| x == parts.last ? x.singularize.camelize : x.camelize}.join("::")
    end

    def get_object
      @object = @abstract_model.get(params[:id])
      not_found unless @object
    end

    def check_scope_on_query
      return if not request.format.html?
      return if not @scope_adapter or not @authorization_adapter
      return if @scope_adapter.models.map{|m| m.name}.include?(@abstract_model.model.name)
      @scope_adapter.models.each do |model|
        assoc = @abstract_model.belongs_to_associations.map{|a| a if a[:parent_model].name == model.name}.first
        if @object and assoc and assoc.length > 0 then
          record = @object.send assoc[:name]
          raise CanCan::AccessDenied if record.id != @current_scope_parameters[model.name].to_i
        end
        raise CanCan::AccessDenied if not params.include?(model.name)
      end
    end

    private

    def _get_scope_parameters!
      @current_scope_parameters = {}
      return if not session.include? 'scope'      
      session[:scope].each do |model, value|
        @current_scope_parameters[model] = value
      end
      @current_scope_parameters
    end

    def _scope!
      instance_eval &RailsAdmin.scope_with
    end

    def _get_scope_models!
      get_scope_models if @scope_adapter
    end

    def _authenticate!
      instance_eval &RailsAdmin.authenticate_with
    end

    def _authorize!
      instance_eval &RailsAdmin.authorize_with
    end

    def _current_user
      instance_eval &RailsAdmin.current_user_method
    end

    def set_plugin_name
      @plugin_name = "Admin Center"
    end

    def not_found
      render :file => Rails.root.join('public', '404.html'), :layout => false, :status => 404
    end

    def rails_admin_controller?
      true
    end
  end
end
