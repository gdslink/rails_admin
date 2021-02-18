require 'openssl'
require 'base64'

module RailsAdmin
  module Config
    module Actions
      class AssetAction < RailsAdmin::Config::Actions::Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option :collection do
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
              if params[:picture]              
                tempFile = params[:picture].tempfile
                file = File.open(tempFile)
                picture_asset = PictureAsset.new
                picture_asset.data_file_name = params[:picture].original_filename
                picture_asset.data_content_type = params[:picture].content_type
                if(["image/png", "image/jpeg", "image/jpg", "image/gif", "image/tiff"].include? picture_asset.data_content_type)
                  if(CaseCenter::Config::Reader.get('mongodb_attachment_database'))
                    Mongoid.override_client(:attachDb)
                  end
                  begin
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
                    encThumbData << cipher.final
                    File.open(thumbFile, 'wb') do |f|
                      f.write(encThumbData)
                    end

                    cipher2 = OpenSSL::Cipher.new('aes-256-cbc')
                    cipher2.encrypt
                    cipher2.key = key
                    encData = cipher2.update(File.read(file))
                    encData << cipher2.final
                    File.open(file, 'wb') do |f|
                      f.write(encData)
                    end
                    encrypted_aes = Base64.encode64(public_key.public_encrypt(key))
                    picture_asset.aes_key = encrypted_aes

                    #End of encryption block
                    grid_file = grid_fs.put(file.path)
                    picture_asset.data_file_size = File.size(tempFile).to_i
                    picture_asset.company_id = params[:Company].to_i
                    picture_asset.image_id = grid_file.id
                    grid_thumb_file = grid_fs.put(thumbFile.path)
                    picture_asset.thumb_image_id = grid_thumb_file.id
                  ensure
                    Mongoid.override_client(:default)
                  end
                  thumbFile.close
                  File.delete(thumbFile.path)
                  if picture_asset.save
                    invalidate_cache_key(@model_name)
                    @auditing_adapter && @auditing_adapter.create_object(picture_asset, @abstract_model, _current_user)
                    respond_to do |format|
                      format.html { redirect_to_on_success }
                      format.js { render json: {id: picture_asset.id.to_s, label: @model_config.with(object: picture_asset).object_label} }
                    end
                  else
                    if(CaseCenter::Config::Reader.get('mongodb_attachment_database'))
                      Mongoid.override_client(:attachDb)
                    end
                    begin
                      grid_fs.delete(picture_asset.image_id)
                      grid_fs.delete(picture_asset.thumb_image_id)
                    ensure
                      Mongoid.override_client(:default)
                    end
                    picture_asset.errors.full_messages.each do |message|
                      flash[:error] = message
                    end
                  end
                else
                  flash[:error] = "Upload must be an image"
                end
              else
                flash[:error] = I18n.t('asset_action_no_file')   
              end
            end
          end
        end

        register_instance_option :link_icon do
          'icon-list-alt'
        end

        register_instance_option :visible? do
          is_visible = authorized?
          if !bindings[:controller].current_user.is_root && !bindings[:controller].current_user.is_admin && !bindings[:abstract_model].try(:model_name).nil?
            model_name = bindings[:controller].abstract_model.model_name
            is_visible = (bindings[:controller].current_ability.can? :"asset_action_#{model_name}", bindings[:controller].current_scope["Company"][:selected_record]) && model_name == "PictureAsset"
          end
          is_visible
        end

      end
    end
  end
end
