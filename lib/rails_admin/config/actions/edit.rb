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
                if @model_name == "Email"
                  patId = Pattern.where(:application_id=>User.current_user.current_scope['Application'], :name=>params[:pattern_id]).pluck(:_id)[0]
                  @object.pattern_id = patId.to_s
                  @object.save
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

                if @model_name == "Pattern"
                  if params[:pattern][:pattern_type] =="pdf"
                    @object.html_block_id = HtmlBlock.where(:application_id=>User.current_user.current_scope['Application'], :name=>params[:email][:pattern_id]).pluck(:id)[0]
                    @object.html_block_key = HtmlBlock.where(:application_id=>User.current_user.current_scope['Application'], :name=>params[:email][:pattern_id]).pluck(:key)[0]
                    @object.save
                  else
                    @object.pattern_file_name = params[:pattern_file_input].original_filename
                    tempFile = params[:pattern_file_input].tempfile
                    file = File.open(tempFile)
                    if params[:pattern_file_input].content_type == "text/csv" || params[:pattern_file_input].content_type == "application/vnd.ms-excel" || params[:pattern_file_input].content_type == "application/rtf"
                      if(CaseCenter::Config::Reader.get('mongodb_attachment_database'))
                        Mongoid.override_client(:attachDb)
                      end
                      grid_fs = Mongoid::GridFS
                      encData = Mongoid::EncryptedFields.cipher.encrypt(file.read)
                      File.open(file, 'wb') do |f|
                        f.write(encData)
                      end
                      grid_file = grid_fs.put(file.path)
                      @object.pattern_file_id = grid_file.id
                      Mongoid.override_client(:default)
                      @object.save
                    else
                      flash[:error] = "Upload must be an rtf/csv"
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
