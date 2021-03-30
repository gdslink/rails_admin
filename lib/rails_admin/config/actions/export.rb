module RailsAdmin
  module Config
    module Actions
      class Export < RailsAdmin::Config::Actions::Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option :collection do
          true
        end

        register_instance_option :http_methods do
          [:get, :post]
        end

        register_instance_option :pjax? do
          false
        end

        register_instance_option :controller do
          proc do
            if format = params[:json] && :json || params[:csv] && :csv || params[:xml] && :xml
              raise ArgumentError.new I18n.t("admin.export.empty_fields_error") if params["schema"].nil?
              request.format = format
              @schema = HashHelper.symbolize(params[:schema]) if params[:schema] # to_json and to_xml expect symbols for keys AND values.
              @objects = list_entries(@model_config, :export)
              index
            else
              render @action.template_name
            end
          end
        end

        register_instance_option :bulkable? do
          true
        end

        register_instance_option :link_icon do
          'icon-share'
        end

        register_instance_option :visible? do
          is_visible = authorized?
          if !bindings[:controller].current_user.is_root && !bindings[:controller].current_user.is_admin && !bindings[:abstract_model].try(:model_name).nil?
            model_name = bindings[:controller].abstract_model.model_name
            is_visible = bindings[:controller].current_ability.can? :"export_#{model_name}", bindings[:controller].current_scope["Application"][:selected_record]
          end
          is_visible
        end

      end
    end
  end
end
