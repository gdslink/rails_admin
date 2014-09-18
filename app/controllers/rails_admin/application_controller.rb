require 'rails_admin/abstract_model'

module RailsAdmin
  class ApplicationController < ::ApplicationController
    newrelic_ignore if defined?(NewRelic)

    before_filter :_authenticate!
    before_filter :_authorize!
    before_filter :_scope!
    before_filter :set_timezone
    before_filter :set_locale
    before_filter :set_plugin_name

    before_filter :_get_scope_models!
    before_filter :_get_scope_parameters!

    helper_method :_current_user, :_attr_accessible_role
    helper_method :cache_key

    def cache_key(model_name, depends = true)
      signature = model_name

      signature = model_name.constantize.reflect_on_all_associations.map{ |c|
        _cache_key_for_model(c.class_name)
      }.join(',') if depends

      Rails.cache.fetch(Digest::SHA1.hexdigest("admin/cache_key/#{@current_scope_parameters.to_s}/#{signature}")) do
        signature.to_s + Time.now.to_i.to_s
      end
    end

    def _cache_key_for_model(model_name)
      Rails.cache.fetch("admin/cache_key/#{@current_scope_parameters.to_s}/#{model_name}") do
        model_name.to_s + Time.now.to_i.to_s
      end
    end

    def invalidate_cache_key(model_name)
      Rails.cache.delete("admin/cache_key/#{@current_scope_parameters.to_s}/#{model_name}")
    end

    def set_timezone
      Time.zone = current_user.time_zone if current_user
    end

    def set_locale
      I18n.locale = get_locale || extract_locale_from_accept_language_header
    end

    def default_url_options(options={})
      options.merge({ :locale => I18n.locale })
    end

    def get_model
      @model_name = to_model_name(params[:model_name])
      @abstract_model = RailsAdmin::AbstractModel.new(@model_name)
      @model_config = RailsAdmin.config(@abstract_model)
      not_found if @model_config.excluded?
      @properties = @abstract_model.properties
    end

    def to_model_name(param)
      parts = param.split("~")
      parts[-1] = parts.last.singularize
      parts.map(&:camelize).join("::")
    end

    def get_object
      @object = @abstract_model.get(params[:id])
      not_found unless @object
    end

    def check_scope_on_query
      return if not request.format or not request.format.html?
      return if not @scope_adapter or not @authorization_adapter
      return if @scope_adapter.models.map{|m| m.name}.include?(@abstract_model.model.name)
      @scope_adapter.models.each do |model|
        assoc = @abstract_model.belongs_to_associations.map{|a| a if  a[:parent_model].respond_to? :name and a[:parent_model].name == model.name}.reject{|a| a.nil?}.first
        if @object and assoc and assoc.length > 0 then
          record = @object.send assoc[:name]
          raise CanCan::AccessDenied if record.id != @current_scope_parameters[model.name].to_i
        end
        raise CanCan::AccessDenied if not params.include?(model.name)
      end
    end

    private

    def get_locale
      locale = params[:locale].to_s
      return locale if I18n.available_locales.include?(locale.to_sym) unless locale.empty?
      nil
    end


    def extract_locale_from_accept_language_header
      request.env['HTTP_ACCEPT_LANGUAGE'].scan(/^[a-z]{2}/).first if request.env['HTTP_ACCEPT_LANGUAGE']
    end 

    def _get_scope_parameters!
      @current_scope_parameters = {}
      return if not session.include? :scope
      session[:scope].each do |model, value|
        @current_scope_parameters[model] = value
      end
      @current_scope_parameters
    end

    def _scope!
      instance_eval &RailsAdmin::Config.scope_with
    end

    def _get_scope_models!
      get_scope_models if @scope_adapter
    end

    def _authenticate!
      instance_eval &RailsAdmin::Config.authenticate_with
    end

    def _authorize!
      instance_eval &RailsAdmin::Config.authorize_with
    end

    def _current_user
      instance_eval &RailsAdmin::Config.current_user_method
    end
    
    def _attr_accessible_role
      instance_eval &RailsAdmin::Config.attr_accessible_role
    end
    
    def set_plugin_name
      @plugin_name_array = [instance_eval(&RailsAdmin.config.main_app_name)].flatten
      @plugin_name = @plugin_name_array.join(' ')
    end

    def not_found
      render :file => Rails.root.join('public', '404.html'), :layout => false, :status => 404
    end

    def rails_admin_controller?
      true
    end
  end
end
