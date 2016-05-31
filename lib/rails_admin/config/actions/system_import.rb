require 'rails_admin/config/actions'
require 'rails_admin/config/actions/base'

module RailsAdmin
  module Config
    module Actions
      class SystemImport < RailsAdmin::Config::Actions::Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option :collection? do
          true
        end

        register_instance_option :http_methods do
          [:get, :post]
        end

        register_instance_option :controller do
          proc do
            #@authorization_adapter.authorize(:system_import, @abstract_model, @object) if @authorization_adapter
            mode = params["mode"] rescue nil
            @model_name = params[:model_name]
            if mode.nil?
              @object = @abstract_model.new #we do not have an object yet, so create one
              @page_name = t("admin.actions.system_import").capitalize
              @page_type = t("admin.actions.system_import").capitalize

              respond_to do |format|
                format.html { render :layout => 'rails_admin/form' }
                format.js   { render :layout => 'rails_admin/plain.html.erb' }
              end
            elsif mode == "upload_iframe"
              render :template => 'rails_admin/main/upload_file_form', :layout => nil
            elsif mode == "upload_file"
              begin
                if Rails.cache.exist?(:import_in_progress)
                  raise Exception.new(I18n.t('admin.import_export.error_in_progress'))
                end

                @import_details = CaseCenter::ImportExport.new.get_company_and_application(params["import_file"].tempfile.path)
                Rails.cache.write(:import_temporary_file, Base64.encode64(params["import_file"].read), :expires_in => 5.minutes)
              rescue Exception => e
                Rails.logger.error("Error while importing #{e.message}")
                Rails.logger.error(e.backtrace.join("\n"))
                @error = e.message.squish
              end
              render :template => 'rails_admin/main/upload_file_complete', :layout => nil
            elsif mode == "install_import"
              begin
                @details = {
                    :application_name => params['application_name'],
                    :application_key => params['application_key']
                }

                if Rails.cache.exist?(:import_in_progress)
                  raise Exception.new(I18n.t('admin.import_export.error_in_progress'))
                end

                in_file = Rails.cache.fetch(:import_temporary_file)
                if in_file.nil?
                  raise Exception.new(I18n.t('admin.import_export.error_expired'))
                end

                Rails.cache.write(:import_in_progress, true, :expires_in => 15.minutes)
                Rails.cache.delete(:import_last_error)

                if current_user.is_root?
                  @details[:company_key] = params['company_key']
                  @details[:company_name] = params['company_name']
                else
                  if current_user.is_admin?
                    @company = ::Company.find(@current_user.company_id)

                    if(@company.key != params['company_key'])
                      raise Exception.new(I18n.t('admin.import_export.error_no_permission', :company_name => @company.name))
                    end

                    @details[:company_key] = @company.key
                    @details[:company_name] = @company.name
                  else
                    raise Exception.new(I18n.t('admin.import_export.error_user_no_permission'))
                  end
                end

                Thread.new(@details, Base64.decode64(in_file), @company) do |details, file_data, company|
                  ActiveRecord::Base.connection_pool.with_connection do
                    f = Tempfile.new('cc')
                    begin
                      SystemImportMailer.notify_email({email: current_user.email,
                                                       company_name: details[:company_name],
                                                       application_name: details[:application_name],
                                                       status: t('admin.import_export.email_status.processed'),
                                                       body: t('admin.import_export.email_body_processed')}).deliver

                      f.binmode
                      f.write(file_data)
                      f.close()
                      CaseCenter::ImportExport.new.import(f.path, details)
                      company = ::Company.where(:key => details[:company_key]).first
                      application = ::Application.where(:key => details[:application_key]).where(:company_id => company.id).first
                      application.generate_mongoid_model(true)
                      Rails.cache.write(:import_company_data, {
                          :company_name => company.name,
                          :company_id => company.id,
                          :application_name => application.name,
                          :application_id => application.id,
                      }, :expires_in => 5.minutes)
                      SystemImportMailer.notify_email({email: current_user.email,
                                                       company_name: details[:company_name],
                                                       application_name: details[:application_name],
                                                       status: t('admin.import_export.email_status.complete'),
                                                       body: t('admin.import_export.import_successful')}).deliver
                    rescue Exception => e
                      Rails.logger.error("Error while importing #{e.message}")
                      Rails.logger.error(e.backtrace.join("\n"))
                      Rails.cache.write(:import_last_error, I18n.t('admin.import_export.error', :message => e.message), :expires_in => 5.minutes)
                      SystemImportMailer.notify_email({email: current_user.email,
                                                       company_name: details[:company_name],
                                                       application_name: details[:application_name],
                                                       status: t('admin.import_export.email_status.failed'),
                                                       body: t('admin.import_export.error', message: "#{e.message} \n #{e.backtrace}")}).deliver
                    ensure
                      Rails.cache.delete(:import_in_progress)
                      f.unlink() unless f.nil?
                    end
                  end
                end
              rescue Exception => e
                Rails.cache.write(:import_last_error, I18n.t('admin.import_export.error', :message => e.message), :expires_in => 5.minutes)
                Rails.cache.delete(:import_in_progress)
                Rails.logger.error("Error while importing #{e.message}")
                Rails.logger.error(e.backtrace.join("\n"))
                @error =  e.message.squish
              end
              render :template => 'rails_admin/main/system_import_complete', :layout => nil
            elsif mode == "check_complete"
              json = {}
              if Rails.cache.exist?(:import_in_progress)
                json[:status] = "In Progress"
                json[:error] = false
              else
                if Rails.cache.exist?(:import_last_error)
                  json[:status] = "Import Error"
                  json[:error] = true
                  json[:error_description] = Rails.cache.fetch(:import_last_error)
                elsif Rails.cache.exist?(:import_company_data)
                  json[:status] = "Import Complete"
                  json[:error] = false
                  icd = Rails.cache.fetch(:import_company_data)
                  icd.each_pair do |k, v|
                    json[k] = v
                  end
                else
                  json[:status] = "Import Error"
                  json[:error] = true
                  json[:error_description] = "Unknown status"
                end
              end
              render :json => json.to_json
            end
          end
        end

        register_instance_option :custom_key do
          :system_import
        end

        register_instance_option :authorization_key do
          :system_import
        end

      end
    end
  end
end