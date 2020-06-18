module RailsAdmin
  module Config
    module Actions
      class New < RailsAdmin::Config::Actions::Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option :collection do
          true
        end

        register_instance_option :http_methods do
          [:get, :post] # NEW / CREATE
        end

        register_instance_option :controller do
          proc do
            if request.get? # NEW
              @object = @abstract_model.new
              @authorization_adapter && @authorization_adapter.attributes_for(:new, @abstract_model).each do |name, value|
                @object.send("#{name}=", value)
              end
              if object_params = params[@abstract_model.to_param]
                @object.set_attributes(@object.attributes.merge(object_params))
              end
              respond_to do |format|
                format.html { render @action.template_name }
                format.js   { render @action.template_name, layout: false }
              end

            elsif request.post? # CREATE
              @modified_assoc = []
              @object = @abstract_model.new
              sanitize_params_for!(request.xhr? ? :modal : :create)
              @object.check_child_parents = true if @model_name == "Table" #set flag on this object specifially, so that rails doesn't try to validate each child too
              @object.set_attributes(params[@abstract_model.param_key])
              @authorization_adapter && @authorization_adapter.attributes_for(:create, @abstract_model).each do |name, value|
                @object.send("#{name}=", value)
              end
              if @object.save
                if @model_name == "Company"
                  if params[:picture].present?
                    tempFile = params[:picture].tempfile
                    file = File.open(tempFile)
                    picture_asset = PictureAsset.new
                    picture_asset.data_file_name = params[:picture].original_filename
                    picture_asset.data_content_type = params[:picture].content_type
                    if(["image/png", "image/jpeg", "image/jpg", "image/gif"].include? picture_asset.data_content_type)
                      if(CaseCenter::Config::Reader.get('mongodb_attachment_database'))
                        Mongoid.override_client(:attachDb)
                      end
                      grid_fs = Mongoid::GridFS
                      thumbFilename = params[:picture].original_filename
                      line = Terrapin::CommandLine.new("convert", ":in -scale :resolution :out")
                      line.run(in: tempFile.path, resolution: "30x30", out: thumbFilename)
                      thumbFile = File.open(thumbFilename)

                      #Encryption
                      public_key_file = CaseCenter::Config::Reader.get('attachments_public_key');
                      public_key = OpenSSL::PKey::RSA.new(File.read(public_key_file))
                      cipher = OpenSSL::Cipher.new('aes-256-cbc')
                      cipher.encrypt
                      key = cipher.random_key
                      encThumbData = cipher.update(File.read(thumbFile))
                      File.open(thumbFile, 'wb') do |f|
                        f.write(encThumbData)
                      end
                      encData = cipher.update(File.read(file))
                      File.open(file, 'wb') do |f|
                        f.write(encData)
                      end
                      encrypted_aes = Base64.encode64(public_key.public_encrypt(key))
                      picture_asset.aes_key = encrypted_aes

                      grid_file = grid_fs.put(file.path)
                      picture_asset.data_file_size = File.size(tempFile).to_i
                      picture_asset.company_id = params[:Company].to_i
                      picture_asset.image_id = grid_file.id
                      grid_thumb_file = grid_fs.put(thumbFile.path)
                      picture_asset.thumb_image_id = grid_thumb_file.id
                      thumbFile.close
                      File.delete(thumbFile.path)
                      if(CaseCenter::Config::Reader.get('mongodb_attachment_database'))
                        Mongoid.override_client(:default)
                      end
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
                    fsf.add_read_only(params[:checkboxes])
                  end
                end
                @application.generate_mongoid_model if ["Field", "Status", "Table"].include? @model_name
                @auditing_adapter && @auditing_adapter.create_object(@object, @abstract_model, _current_user)
                respond_to do |format|
                  format.html { redirect_to_on_success }
                  format.js   { render json: {id: @object.id.to_s, label: @model_config.with(object: @object).object_label} }
                end
              else
                if params[:user].present?
                  if params[:user][:user_property_list].present?
                    @userPropertyValues = params[:user][:user_property_list]
                  end
                end
                handle_save_error
              end

              invalidate_cache_key(@model_name)
            end
          end
        end

        register_instance_option :link_icon do
          'icon-plus'
        end

        register_instance_option :pjax? do
          false
        end
      end
    end
  end
end
