require 'zip'
require 'fileutils'

module RailsAdmin
  module Config
    module Actions
      class XslAction < RailsAdmin::Config::Actions::Base
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
              if(params[:stylesheet]) then
                tempFile = params[:stylesheet].tempfile
                file = File.open(tempFile)

                zipLocation = params[:stylesheet].original_filename[0..-5]
                if File.directory?(Rails.root.join('public','xsl',zipLocation))
                  FileUtils.rm_rf(Rails.root.join('public','xsl',zipLocation))
                end
                Dir.mkdir(Rails.root.join('public','xsl',zipLocation))

                Zip::File.open(file.path) do |zipFile|
                  zipFile.each do |curFile|
                    if curFile.ftype == :directory
                      FileUtils.mkdir_p(Rails.root.join('public','xsl',zipLocation,curFile.name))
                    else
                      path = File.join(Rails.root.join('public','xsl',zipLocation),curFile.name)
                      File.open(path, 'wb') do |f|
                        f.write(curFile.get_input_stream.read)
                      end
                    end
                  end
                end

                stylesheet = XslSheet.new()
                stylesheet.data_file_name = params[:stylesheet].original_filename
                stylesheet.company_id = params[:Company].to_i
                if params[:stylesheet].content_type == "application/zip" || params[:stylesheet].content_type == "application/x-zip-compressed"
                  if(CaseCenter::Config::Reader.get('mongodb_attachment_database'))
                    Mongoid.override_client(:attachDb)
                  end
                  begin
                    grid_fs = Mongoid::GridFS

                    #Encryption
                    public_key_file = CaseCenter::Config::Reader.get('attachments_public_key');
                    public_key = OpenSSL::PKey::RSA.new(File.read(public_key_file))
                    cipher = OpenSSL::Cipher.new('aes-256-cbc')
                    cipher.encrypt
                    key = cipher.random_key
                    encData = cipher.update(File.read(file))
                    encData << cipher.final
                    #End Encryption
                    
                    File.open(file, 'wb') do |f|
                      f.write(encData)
                    end
                    encrypted_aes = Base64.encode64(public_key.public_encrypt(key))
                    stylesheet.aes_key = encrypted_aes
                    stylesheet.entry_point = params[:entryPoint]
                    grid_file = grid_fs.put(file.path)
                    stylesheet.stylesheet_id = grid_file.id                
                  ensure
                    Mongoid.override_client(:default)
                  end
                  if stylesheet.save
                    respond_to do |format|
                      format.html { redirect_to_on_success }
                      format.js { render json: {id: stylesheet.id.to_s, label: @model_config.with(object: stylesheet).object_label} }
                    end
                  else 
                    if(CaseCenter::Config::Reader.get('mongodb_attachment_database'))
                      Mongoid.override_client(:attachDb)
                    end
                    begin
                      grid_fs.delete(stylesheet.stylesheet_id)
                    ensure
                      Mongoid.override_client(:default)
                    end
                    FileUtils.rm_rf(Rails.root.join('public','xsl',zipLocation))
                    stylesheet.errors.full_messages.each do |message|
                      flash[:error] = message
                    end
                  file.close
                  File.delete(file.path)
                  end
                else 
                  flash[:error] = "Upload must be an XSL file"
                end
              else
                flash[:error] = "Please choose a file"
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
