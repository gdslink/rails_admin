require 'rails_admin/abstract_model'

module RailsAdmin
  class ModelNotFound < ::StandardError
  end

  class ObjectNotFound < ::StandardError
  end

  class ActionNotAllowed < ::StandardError
  end

  class ApplicationController < Config.parent_controller.constantize
    protect_from_forgery with: :exception
    newrelic_ignore if defined?(NewRelic)

    before_filter :_authenticate!
    before_filter :_authorize!
    before_filter :_scope!
    before_filter :_scope_current_user!
    before_filter :_get_scope_models!
    before_filter :_get_scope_parameters!
    before_filter :_audit!

    before_filter :_set_timezone
    before_filter :_set_locale


    helper_method :_current_user, :_get_plugin_name, :cache_key

    attr_reader :object, :model_config, :abstract_model, :authorization_adapter

    def invalidate_cache_key(model_name)
      Rails.cache.delete(Digest::SHA1.hexdigest("admin/cache_key/#{session[:scope].to_s}/#{model_name}"))
    end

    def cache_key(model_name, depends = true)
      signature = model_name
      m = []
      if depends
        m = model_name.constantize.reflect_on_all_associations.map{ |c|
          _cache_key_for_model(c.class_name)
        } if model_name.respond_to? :constantize
        m << _cache_key_for_model(model_name)
        signature = m.join(',')
      else
        signature = _cache_key_for_model(model_name)
      end

      cache_name = Digest::SHA1.hexdigest("admin/cache_key/#{signature}")
      cache_name
    end

    def get_model
        model_name = params[:model_name]
      @model_name = to_model_name(model_name)
      fail(RailsAdmin::ModelNotFound) unless (@abstract_model = RailsAdmin::AbstractModel.new_new(@model_name))
      fail(RailsAdmin::ModelNotFound) if (@model_config = @abstract_model.config).excluded?
      @properties = @abstract_model.properties
    end

    def get_object
      Mongoid.override_client(:default)
      fail(RailsAdmin::ObjectNotFound) unless (@object = @abstract_model.get(params[:id]))
    end

    def to_model_name(param)
      param.to_s.split('~').collect(&:camelize).join('::')
    end

    def _current_user
      #if CaseCenter::Config::Reader.get('saml_authentication') == false
        auth_user = instance_eval(&RailsAdmin::Config.current_user_method)

        if(CaseCenter::Config::Reader.get('saml_authentication') == false && auth_user) then
          mfa_enabled = auth_user.roles.map(&:enable_mfa).include? true
          if ( mfa_enabled and auth_user.gauth_enabled != "1") then
            sign_out auth_user
            redirect_to "/"
          end
        end

        auth_user
      #end
    end

    private

    def _set_timezone
      Time.zone = current_user.time_zone if current_user
    end

    def _set_locale
      unless extract_locale_from_accept_language_header.nil? && get_locale.nil?
        if I18n.available_locales.index(get_locale || extract_locale_from_accept_language_header.to_sym)
          I18n.locale = get_locale || extract_locale_from_accept_language_header
        else
          I18n.locale = I18n.default_locale
        end
      end
    end


    def _cache_key_for_model(model_name)
      Rails.cache.fetch(Digest::SHA1.hexdigest("admin/cache_key/#{session[:scope].to_s}/#{model_name}")) do
        model_name.to_s + Time.now.to_i.to_s
      end
    end

    def _get_plugin_name
      @plugin_name_array ||= [RailsAdmin.config.main_app_name.is_a?(Proc) ? instance_eval(&RailsAdmin.config.main_app_name) : RailsAdmin.config.main_app_name].flatten
    end

    def _authenticate!
      instance_eval(&RailsAdmin::Config.authenticate_with)
    end

    def _authorize!
      if CaseCenter::Config::Reader.get('saml_authentication') == false
        instance_eval(&RailsAdmin::Config.authorize_with)
      end
    end

    def _scope_current_user!
      User.current_user = self.current_user
    end

    def _audit!
      instance_eval(&RailsAdmin::Config.audit_with)
    end

    def _scope!
      instance_eval(&RailsAdmin::Config.scope_with)
    end

    def _get_scope_models!(expire_cache = nil)
      get_scope_models(expire_cache) if @scope_adapter
    end

    def _get_scope_parameters!
      @current_scope_parameters = {}
      return if not session.include? :scope
      session[:scope].each do |model, value|
        @current_scope_parameters[model] = value
      end
      @current_scope_parameters
      current_user.current_scope = @current_scope_parameters
    end

    def get_scope_parameters_to_params_for_model
      return true
    end

    def check_scope_on_query
      return if not request.format or not request.format.html?
      return if not @scope_adapter or not @authorization_adapter
      return if @scope_adapter.models.map{|m| m.name}.include?(@abstract_model.model.name)
      @scope_adapter.models.each do |model|
        if @abstract_model.model.name != "PictureAsset" && @abstract_model.model.name != "XslSheet" && @abstract_model.model.name != "Pattern" && @abstract_model.model.name != "TestRecord"
          assoc = @abstract_model.belongs_to.map{|a|
            a if  a.association and a.association.name.to_s.downcase == model.name.downcase}.reject{|a| a.nil?
          }.first
          if @object and assoc then
            record = @object.send assoc.association.name
            raise CanCan::AccessDenied if record.id != @current_scope_parameters[model.name].to_i
          end
          raise CanCan::AccessDenied if assoc != nil and not params.include?(model.name)
        else

        end
      end
    end


    alias_method :user_for_paper_trail, :_current_user

    def user_for_paper_trail
      _current_user.try(:id) || _current_user
    end


    rescue_from RailsAdmin::ObjectNotFound do
      flash[:error] = I18n.t('admin.flash.object_not_found', model: @model_name, id: params[:id])
      params[:action] = 'index'
      index
    end

    rescue_from RailsAdmin::ModelNotFound do
      flash[:error] = I18n.t('admin.flash.model_not_found', model: @model_name)
      params[:action] = 'dashboard'
      dashboard
    end
  end
end
