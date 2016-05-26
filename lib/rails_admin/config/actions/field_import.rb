require 'rails_admin/config/actions'
require 'rails_admin/config/actions/base'

module RailsAdmin
  module Config
    module Actions
      class FieldImport < RailsAdmin::Config::Actions::Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option :collection? do
          true
        end

        register_instance_option :http_methods do
          [:get, :post]
        end

        register_instance_option :controller do
          proc do
            @model_name = params[:model_name]
            field_columns = Field.column_names.collect { |x| x == "table_id" ? "table_key" : x } # change table_id to table_key

            if params[:mode] == "upload"
              @csv = CSV.read(params["fields"].tempfile.path)
              invalid_column = @csv[0] - field_columns
              unless invalid_column.empty?
                flash[:error] = "Invalid columns found: #{invalid_column.join(", ")}"
                @error = true
              end
            elsif params[:mode] == "import"
              records = []
              params[:valid].each do |index|
                h = {:field => params[:field][index.to_i].delete_if { |key, value| value.to_s.strip == '' }.merge!({"application_id" => @application.id})}
                parameters = ActionController::Parameters.new(h)
                parameters.require(:field).permit(:application_id, :field_type, :key, :name)
                records << Field.new(parameters)
              end
              @result = Field.import records, :on_duplicate_key_update => [:application_id, :key]
              if @result.failed_instances.length == 0
                flash[:notice] = t("admin.flash.successful", :name => pluralize(records.size, @model_config.label), :action => t("admin.actions.system_imported"))
                @application.generate_mongoid_model
              else
                flash[:error] = t("admin.flash.error", :name => pluralize(records.size, @model_config.label), :action => t("admin.actions.system_imported"))
              end
              redirect_to list_path(@current_scope_parameters) and return
            elsif params[:mode] == "download"
              columns_list = field_columns.reject do |f|
                %W(id application_id created_at updated_at field_format).include?(f)
              end

              res = CSV.generate do |csv|
                csv << columns_list
              end
              send_data res, :filename => "Fields_Import_Template.csv", :type => "text/csv"
            elsif params[:mode] == "ajax"
              attr = JSON.parse(params[:field])
              tbl = Query::FieldTable.new(@authorization_adapter, @scope_adapter).tables.inject({}) do |h, object|
                h[object.key] = object.id
                h
              end
              tbl.to_a

              fld_types = Hash[*(Field.new.field_type_enum.flatten.map {|d| d.to_s})]
              attr.delete_if { |key, value| value.to_s.strip == '' }.merge({"application_id" => @application.id})
              field = Field.get_field_and_validate(attr.merge({"application_id" => @application.id}), tbl, fld_types)

              render :json => { "errors" => field.errors.full_messages.join(", ")}
            end

            unless params[:mode] == "download" or params[:mode] == "ajax"
              render :layout => 'rails_admin/application'
            end

          end
        end

        register_instance_option :link_icon do
          'icon-upload'
        end
        
        register_instance_option :visible? do
          authorized? && bindings[:abstract_model].model_name == 'Field'
        end

        register_instance_option :custom_key do
          :field_import
        end

        register_instance_option :authorization_key do
          :field_import
        end

      end
    end
  end
end