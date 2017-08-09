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

    before_action :_authenticate!
    before_action :_authorize!
    before_action :_scope!
    before_action :_scope_current_user!
    before_action :_get_scope_models!
    before_action :_get_scope_parameters!
    before_action :_audit!
    before_action :_set_timezone
    before_action :_set_locale


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
      @model_name = to_model_name(params[:model_name])
      raise(RailsAdmin::ModelNotFound) unless (@abstract_model = RailsAdmin::AbstractModel.new(@model_name))
      raise(RailsAdmin::ModelNotFound) if (@model_config = @abstract_model.config).excluded?
      @properties = @abstract_model.properties
    end

    def get_object
      raise(RailsAdmin::ObjectNotFound) unless (@object = @abstract_model.get(params[:id]))
    end

    def to_model_name(param)
      param.to_s.split('~').collect(&:camelize).join('::')
    end

    def _current_user
      instance_eval(&RailsAdmin::Config.current_user_method)
    end

    private

    def check_admin_access
      unless current_user.is_root?
        t = Time.now
        st = "#{CaseCenter::Config::Reader.get("admin_access_start_time")}"
        et = "#{CaseCenter::Config::Reader.get("admin_access_end_time")}"
        if !st.blank? && !et.blank?
          hr, min = st.split(":")
          startTime = Time.new(t.year, t.month, t.day, hr, min)
          hr, min = et.split(":")
          endTime = Time.new(t.year, t.month, t.day, hr, min)
          if t.between?(startTime, endTime)
            flash.now[:error] = t('admin.access.time_window', :start_time => st, :end_time => et)
            render :file => Rails.root.join('public', '401.html'), :layout => false, :status => 401
          end
        end
      end
    end

    def get_locale
      locale = params[:locale].to_s
      return locale if I18n.available_locales.include?(locale.to_sym) unless locale.empty?
      nil
    end

    def extract_locale_from_accept_language_header
      request.env['HTTP_ACCEPT_LANGUAGE'].scan(/^[a-z]{2}/).first if request.env['HTTP_ACCEPT_LANGUAGE']
    end

    def _set_timezone
      Time.zone = current_user.time_zone if current_user
    end

    def _set_locale
      I18n.locale = get_locale || extract_locale_from_accept_language_header
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
      instance_eval(&RailsAdmin::Config.authorize_with)
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

    def _get_scope_models!
      get_scope_models if @scope_adapter
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
        assoc = @abstract_model.belongs_to.map{|a|
          a if  a.association and a.association.name.to_s.downcase == model.name.downcase}.reject{|a| a.nil?
        }.first
        if @object and assoc then
          record = @object.send assoc.association.name
          raise CanCan::AccessDenied if record.id != @current_scope_parameters[model.name].to_i
        end
        raise CanCan::AccessDenied if assoc != nil and not params.include?(model.name)
      end
    end


    def rails_admin_controller?
      true
    end


    rescue_from RailsAdmin::ObjectNotFound do
      flash[:error] = I18n.t('admin.flash.object_not_found', model: @model_name, id: params[:id])
      params[:action] = 'index'
      @status_code = :not_found
      index
    end

    rescue_from RailsAdmin::ModelNotFound do
      flash[:error] = I18n.t('admin.flash.model_not_found', model: @model_name)
      params[:action] = 'dashboard'
      @status_code = :not_found
      dashboard
    end
  end
end
