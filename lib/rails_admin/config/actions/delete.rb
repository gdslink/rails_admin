module RailsAdmin
  module Config
    module Actions
      class Delete < RailsAdmin::Config::Actions::Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option :member do
          true
        end

        register_instance_option :route_fragment do
          'delete'
        end

        register_instance_option :http_methods do
          [:get, :delete]
        end

        register_instance_option :authorization_key do
          :destroy
        end

        register_instance_option :controller do
          proc do
            if request.get? # DELETE

              respond_to do |format|
                format.html { render @action.template_name }
                format.js   { render @action.template_name, layout: false }
              end

            elsif request.delete? # DESTROY

              redirect_path = nil
              @auditing_adapter && @auditing_adapter.delete_object(@object, @abstract_model, _current_user)
              if @object.destroy
                if @abstract_model.model_name == "PictureAsset"
                  if(CaseCenter::Config::Reader.get('mongodb_attachment_database'))
                    Mongoid.override_client(:attachDb)
                  end
                  grid_fs = Mongoid::GridFS
                  grid_fs.delete(@object.image_id)
                  grid_fs.delete(@object.thumb_image_id)
                  Mongoid.override_client(:default)
                  if(@company.logo_image_file_name == @object.thumb_image_id.to_s)
                    @company.logo_image_file_name = ""
                    @company.save
                  end
                end
                if @abstract_model.model_name == "XslSheet"
                  if(CaseCenter::Config::Reader.get('mongodb_attachment_database'))
                    Mongoid.override_client(:attachDb)
                  end
                  grid_fs = Mongoid::GridFS
                  grid_fs.delete(@object.stylesheet_id.to_s)
                  Mongoid.override_client(:default)
                end
                if @abstract_model.model_name == "Pattern"
                  if(CaseCenter::Config::Reader.get('mongodb_attachment_database'))
                    Mongoid.override_client(:attachDb)
                  end
                  grid_fs = Mongoid::GridFS
                  grid_fs.delete(@object.pattern_file_id.to_s)
                  Mongoid.override_client(:default)
                end
                @application.generate_mongoid_model if ["Field", "Status", "Table"].include? @model_name
                flash[:success] = t('admin.flash.successful', name: @model_config.label, action: t('admin.actions.delete.done'))
                redirect_path = (%w{Company Application}.include? @model_name) ? dashboard_path : index_path
              else
                flash[:error] = t('admin.flash.error', name: @model_config.label, action: t('admin.actions.delete.done'))
                redirect_path = back_or_index
              end
              invalidate_cache_key(@model_name)

              redirect_to redirect_path

            end
          end
        end

        register_instance_option :link_icon do
          'icon-remove'
        end
      end
    end
  end
end
