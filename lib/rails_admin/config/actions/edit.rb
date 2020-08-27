require 'fileutils'

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
              # make a temp copy of the associated objects, so we manually apply updates to them and read changes by utilising ActiveRecord::Dirty:changes
              if @abstract_model.model_name == "Environment"
                old_schedule_values = []
                schedule_changes = {}
                schedule_changes_itemized = {}

                @object.schedule_values.each do |obj|
                  old_schedule_values.push(obj.dup)
                  old_schedule_values.last.id = obj.id
                  old_schedule_values.last.clear_changes_information
                end

                old_env_property_values = []
                env_property_changes = {}
                env_property_changes_itemized = {}

                @object.environment_property_values.each do |obj|
                  old_env_property_values.push(obj.dup)
                  old_env_property_values.last.id = obj.id
                  old_env_property_values.last.clear_changes_information
                end
              end

              if @abstract_model.model_name == "User"
                old_user_properties_values = []
                user_property_changes = {}
                user_property_changes_itemized = {}

                @object.user_property_values.each do |obj|
                  old_user_properties_values.push(obj.dup)
                  old_user_properties_values.last.id = obj.id
                  old_user_properties_values.last.clear_changes_information
                end
              end

              sanitize_params_for!(request.xhr? ? :modal : :update)
              @object.make_associated_attributes_dirty if ["Role", "Table", "User", "Filter", "PopulateAction", "DataViewConnector"].include? @abstract_model.model_name
              @object.check_child_parents = true if @model_name == "Table" #set flag on this object specifially, so that rails doesn't try to validate each child too
              @object.set_attributes(params[@abstract_model.param_key])
              @authorization_adapter && @authorization_adapter.attributes_for(:update, @abstract_model).each do |name, value|
                @object.send("#{name}=", value)
              end
              changes = @object.changes
              changes.delete(:authentication_token)
              changes.each { |k,v| changes.delete(k) if v[0] == v[1] }   # delete the attribute from changes hash if old values = new values

              if @model_name == "Pattern"

                if params[:pattern][:pattern_type] =="pdf"
                  @object.html_block_id = HtmlBlock.where(:application_id=>User.current_user.current_scope['Application'], :name=>params[:email][:pattern_id]).pluck(:id)[0]
                  @object.html_block_key = HtmlBlock.where(:application_id=>User.current_user.current_scope['Application'], :name=>params[:email][:pattern_id]).pluck(:key)[0]
                  @object.pattern_file_name = "" 
                else
                  if params[:pattern_file_input]
                    
                    tempFile = params[:pattern_file_input].tempfile
                    file = File.open(tempFile)

                    currentFileType = Terrapin::CommandLine.new('file', '-b --mime-type :file').run(file: tempFile.path).strip

                    if ["application/rtf","text/rtf","text/csv","text/plain","application/csv","application/vnd.ms-excel"].index(currentFileType) != nil
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
                        #End of Encryption
                        File.open(file, 'wb') do |f|
                          f.write(encData)
                        end
                        encrypted_aes = Base64.encode64(public_key.public_encrypt(key))
                        @object.aes_key = encrypted_aes

                        grid_file = grid_fs.put(file.path)
                        @object.pattern_file_id = grid_file.id
                        @object.pattern_file_name = params[:pattern_file_input].original_filename
                      ensure
                        Mongoid.override_client(:default)
                      end
                      @object.html_block_id = nil
                      @object.html_block_key = ""
                    else
                      flash[:error] = "Upload must be an rtf/csv"
                    end
                  end
                end
              end

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
                      encData = cipher.update(File.read(file))
                      encData << cipher.final
                      File.open(file, 'wb') do |f|
                        f.write(encData)
                      end
                      encrypted_aes = Base64.encode64(public_key.public_encrypt(key))
                      picture_asset.aes_key = encrypted_aes
                      #End of Encryption

                      grid_file = grid_fs.put(file.path)
                      picture_asset.data_file_size = File.size(tempFile).to_i
                      picture_asset.company_id = params[:Company].to_i
                      picture_asset.image_id = grid_file.id
                      grid_thumb_file = grid_fs.put(thumbFile.path)
                      picture_asset.thumb_image_id = grid_thumb_file.id
                      thumbFile.close
                      File.delete(thumbFile.path)
                    ensure
                      Mongoid.override_client(:default)
                    end                                        
                    if picture_asset.save
                      @object.logo_image_file_name = grid_thumb_file.id
                    elsif picture_asset.errors.messages.values[0].include? "is already taken"
                      @object.logo_image_errors = "Logo image filename is already taken"
                    end                    
                  else
                    # flash[:error] = "Upload must be an image"
                    @object.logo_image_errors = "Upload must be an image"
                  end
                end
              end

              if @model_name == "XslSheet"
                if params[:entryPoint]
                  @object.entry_point = params[:entryPoint]
                end
                if params[:stylesheet]
                  tempFile = params[:stylesheet].tempfile
                  file = File.open(tempFile)

                  zipLocation = params[:stylesheet].original_filename[0..-5]
                  if File.directory?(Rails.root.join('public','xsl',zipLocation))
                    FileUtils.rm_rf(Rails.root.join('public','xsl',zipLocation))
                  end
                  Dir.mkdir(Rails.root.join('public','xsl',zipLocation))
                  Zip::File.open(file.path) do |zipFile|
                    zipFile.each do |file|
                      if file.ftype == :directory
                        Dir.mkdir(Rails.root.join('public','xsl',zipLocation,file.name))
                      else
                        path = File.join(Rails.root.join('public','xsl',zipLocation),file.name)
                        File.open(path, 'wb') do |f|
                          f.write(file)
                        end
                      end
                    end
                  end
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
                    @object.aes_key = encrypted_aes
                    grid_file = grid_fs.put(file.path)
                    @object.stylesheet_id = grid_file.id
                    oldPath = Rails.root.join('public', 'xsl', @object.data_file_name[0..-5])
                    FileUtils.rm_rf(oldPath)
                    @object.data_file_name = params[:stylesheet].original_filename
                  ensure
                    Mongoid.override_client(:default)
                  end
                end
              end
              if @object.save

                @object.reload
                if @model_name == "Environment"
                  # handle Environment's schedule values history. apply updates on the temp copies and read changes
                  @object.schedule_values.each_with_index do |obj, i|
                    obj.attributes.keys.each do |attr|
                      if old_schedule_values[i].nil?
                        old_schedule_values.push(obj.dup)
                      else
                        old_schedule_values[i][attr] = obj[attr] unless ["created_at", "updated_at"].include? attr
                      end
                    end
                    schedule_changes.merge!(old_schedule_values[i].changes)
                    ["environment_id", "schedule_id", "key"].each {|k| schedule_changes.delete(k) }
                    schedule_changes_itemized.merge!(schedule_changes)
                    schedule_changes.each{ |k,v| schedule_changes_itemized[obj.key.to_s + "." + k] =  schedule_changes_itemized.delete k    }
                   end
                  changes.merge!(schedule_changes_itemized)

                  # handle Environments property values history. apply updates on the temp copies and read changes
                  @object.environment_property_values.each_with_index do |obj, i|
                    obj.attributes.keys.each do |attr|
                      if old_env_property_values[i].nil?
                        old_env_property_values.push(obj.dup)
                      else
                        old_env_property_values[i][attr] = obj[attr] unless ["created_at", "updated_at"].include? attr
                      end
                    end
                    env_property_changes.merge!(old_env_property_values[i].changes)
                    ["environment_id", "environment_property_id", "key"].each {|k| env_property_changes.delete(k) }
                    env_property_changes_itemized.merge!(env_property_changes)
                    env_property_changes.each{ |k,v| env_property_changes_itemized[obj.key.to_s + "." + k] =  env_property_changes_itemized.delete k    }
                   end
                  changes.merge!(env_property_changes_itemized)
                end

                if @model_name == "User"
                  # handle User's property values history. apply updates on the temp copies and read changes
                  @object.reload
                  @object.user_property_values.each_with_index do |obj, i|
                    obj.attributes.keys.each do |attr|
                      if old_user_properties_values[i].nil?
                        old_user_properties_values.push(obj.dup)
                      else
                        old_user_properties_values[i][attr] = obj[attr] unless ["created_at", "updated_at"].include? attr
                      end
                    end
                    user_property_changes.merge!(old_user_properties_values[i].changes)
                    ["user_id", "company_id", "id", "key"].each {|k| user_property_changes.delete(k) }
                    user_property_changes_itemized.merge!(user_property_changes)
                    user_property_changes.each{ |k,v| user_property_changes_itemized[obj.key.to_s + "." + k] =  user_property_changes_itemized.delete k }
                   end
                   changes.merge!(user_property_changes_itemized)
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
