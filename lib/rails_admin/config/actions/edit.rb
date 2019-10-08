module RailsAdmin
  module Config
    module Actions
      class Edit < RailsAdmin::Config::Actions::Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option :member do
          true
        end

        register_instance_option :http_methods do
          [:get, :put]
        end

        register_instance_option :controller do
          proc do
            if request.get? # EDIT

              respond_to do |format|
                format.html { render @action.template_name }
                format.js   { render @action.template_name, layout: false }
              end

            elsif request.put? # UPDATE
              sanitize_params_for!(request.xhr? ? :modal : :update)
              @object.make_associated_attributes_dirty if ["Role", "Table", "User"].include? @abstract_model.model_name
              @object.set_attributes(params[@abstract_model.param_key])
              @authorization_adapter && @authorization_adapter.attributes_for(:update, @abstract_model).each do |name, value|
                @object.send("#{name}=", value)
              end
              changes = @object.changes
              changes.delete(:authentication_token)
              changes.each { |k,v| changes.delete(k) if v[0] == v[1] }   # delete the attribute from changes hash if old values = new values
              if @object.save
                if @model_name == "Company"
                  if params[:picture].present?
                    tempFile = params[:picture].tempfile
                    file = File.open(tempFile)
                    picture_asset = PictureAsset.new
                    picture_asset.data_file_name = params[:picture].original_filename
                    picture_asset.data_content_type = params[:picture].content_type
                    if(["image/png", "image/jpeg", "image/jpg", "image/gif"].include? picture_asset.data_content_type)
                      grid_fs = Mongoid::GridFS
                      grid_file = grid_fs.put(file.path)
                      picture_asset.data_file_size = File.size(tempFile).to_i
                      picture_asset.assetable_id = @object.id.to_i
                      picture_asset.image_id = grid_file.id
                      thumbFilename = params[:picture].original_filename
                      line = Terrapin::CommandLine.new("convert", ":in -scale :resolution :out")
                      line.run(in: tempFile.path, resolution: "30x30", out: thumbFilename)
                      thumbFile = file = File.open(thumbFilename)
                      grid_thumb_file = grid_fs.put(thumbFile.path)
                      picture_asset.thumb_image_id = grid_thumb_file.id
                      File.delete(thumbFile.path)
                      picture_asset.save
                      @object.logo_image_file_name = grid_thumb_file.id
                      @object.save
                    else
                      flash[:error] = "Upload must be an image"
                    end
                  end
                end
                if params[:checkboxes].present?
                  @object.filter_screen_flows.each do |fsf|
                    if params[:checkboxes].exclude?(fsf.name)
                      fsf.destroy
                    else
                      fsf.add_read_only(params[:checkboxes])
                    end
                  end
                end
                @application.generate_mongoid_model if ["Field", "Status", "Table"].include? @model_name
                @auditing_adapter && @auditing_adapter.update_object(@object, @abstract_model, _current_user, changes) unless changes.empty?
                respond_to do |format|
                  format.html { redirect_to_on_success }
                  format.js { render json: {id: @object.id.to_s, label: @model_config.with(object: @object).object_label} }
                end
              else
                handle_save_error :edit
              end
              invalidate_cache_key(@model_name)
            end
          end
        end

        register_instance_option :link_icon do
          'icon-pencil'
        end

        register_instance_option :pjax? do
          false
        end
      end
    end
  end
end
