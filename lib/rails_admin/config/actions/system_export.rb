require 'rails_admin/config/actions'
require 'rails_admin/config/actions/base'

module RailsAdmin
  module Config
    module Actions
      class SystemExport < RailsAdmin::Config::Actions::Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option :collection? do
          true
        end

        register_instance_option :http_methods do
          [:post]
        end

        register_instance_option :controller do
          proc do
            mode = params["mode"] rescue nil
            @application = ::Application.find(params['id'])
            @company = ::Company.find(@application.company_id)
            @model_name = params['model_name']

            if mode.nil?
              @object = @abstract_model.new #we do not have an object yet, so create one
              @page_name = t("admin.actions.system_export").capitalize
              @page_type = t("admin.actions.system_export").capitalize

              respond_to do |format|
                format.html { render :layout => 'rails_admin/form' }
                format.js   { render :layout => 'rails_admin/plain.html.erb' }
              end
            elsif mode == 'build'
              begin
                target = Tempfile.new('cc')
                target.close
                CaseCenter::ImportExport.new.export(@company.key, @application.key, target.path)
                Rails.cache.delete(:export_temporary_file)

                File.open(target.path, "rb") do |f|
                  Rails.cache.write(:export_temporary_file, Base64.encode64(f.read), :expires_in => 1.minutes)
                end
              rescue Exception => e
                Rails.logger.error("Error while exporting #{e.message}")
                Rails.logger.debug("#{e.backtrace.join('\n')}")
                @error =  e.message
              ensure
                target.unlink unless target.nil?
              end
              render :template => 'rails_admin/main/system_export_download', :layout => nil
            elsif mode == 'download'
              temp_file = Rails.cache.fetch(:export_temporary_file)

              if temp_file.nil?
                Rails.logger.error("Export file download request - file was missing from cache")
                render :text =>"Export file has expired", :status => 500
              else
                send_data Base64.decode64(temp_file),
                          :filename => "#{@company.key}_#{@application.key}_#{Time.now.strftime('%Y%m%d')}.zip",
                          :type => "application/zip"
              end
            end
          end
        end

        register_instance_option :custom_key do
          :system_export
        end

        register_instance_option :authorization_key do
          :system_export
        end

      end
    end
  end
end