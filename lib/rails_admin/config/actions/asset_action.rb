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
              tempFile = params[:picture].tempfile
              file = File.open(tempFile)
              picture_asset = PictureAsset.new
              picture_asset.data_file_name = params[:picture].original_filename
              picture_asset.data_content_type = params[:picture].content_type
              if(["image/png", "image/jpeg", "image/jpg", "image/gif", "image/tiff"].include? picture_asset.data_content_type)
                if(CaseCenter::Config::Reader.get('mongodb_attachment_database'))
                  Mongoid.override_client(:attachDb)
                end
                grid_fs = Mongoid::GridFS
                thumbFilename = params[:picture].original_filename
                line = Terrapin::CommandLine.new("convert", ":in -scale :resolution :out")
                line.run(in: tempFile.path, resolution: "30x30", out: thumbFilename)
                thumbFile = File.open(thumbFilename)
                encThumbData = Mongoid::EncryptedFields.cipher.encrypt(thumbFile.read)
                File.open(thumbFile, 'wb') do |f|
                  f.write(encThumbData)
                end
                encData = Mongoid::EncryptedFields.cipher.encrypt(file.read)
                File.open(file, 'wb') do |f|
                  f.write(encData)
                end
                grid_file = grid_fs.put(file.path)
                picture_asset.data_file_size = File.size(tempFile).to_i
                picture_asset.assetable_id = params[:Company].to_i
                picture_asset.image_id = grid_file.id
                grid_thumb_file = grid_fs.put(thumbFile.path)
                picture_asset.thumb_image_id = grid_thumb_file.id
                File.delete(thumbFile.path)
                Mongoid.override_client(:default)
                if picture_asset.save
                  @auditing_adapter && @auditing_adapter.create_object(picture_asset, @abstract_model, _current_user)
                  respond_to do |format|
                    format.html { redirect_to_on_success }
                    format.js { render json: {id: picture_asset.id.to_s, label: @model_config.with(object: picture_asset).object_label} }
                  end
                else
                  if(CaseCenter::Config::Reader.get('mongodb_attachment_database'))
                    Mongoid.override_client(:attachDb)
                  end
                  grid_fs.delete(picture_asset.image_id)
                  grid_fs.delete(picture_asset.thumb_image_id)
                  Mongoid.override_client(:default)
                  picture_asset.errors.full_messages.each do |message|
                    flash[:error] = message
                  end
                end
              else
                flash[:error] = "Upload must be an image"
              end
            end
          end
        end

        register_instance_option :link_icon do
          'icon-list-alt'
        end
      end
    end
  end
end