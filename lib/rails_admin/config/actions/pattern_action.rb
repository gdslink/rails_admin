module RailsAdmin
  module Config
    module Actions
      class PatternAction < RailsAdmin::Config::Actions::Base
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
              if params[:pattern][:pattern]
                tempFile = params[:pattern][:pattern].tempfile
                file = File.open(tempFile)
                pattern = Pattern.new()
                pattern.name = params[:pattern][:name]
                pattern.description = params[:pattern][:description]
                pattern.pattern_type = params[:pattern][:pattern_type]
                pattern.pattern_file_name = params[:pattern][:pattern].original_filename
                pattern.pattern_file_size = File.size(tempFile).to_i
                pattern.application_id = params[:Application].to_i
                pattern.pattern_content_type = params[:pattern][:pattern].content_type
                if params[:pattern][:pattern].content_type == "text/csv" || params[:pattern][:pattern].content_type == "application/vnd.ms-excel" || params[:pattern][:pattern].content_type == "application/rtf"
                  if(CaseCenter::Config::Reader.get('mongodb_attachment_database'))
                    Mongoid.override_client(:attachDb)
                  end
                  grid_fs = Mongoid::GridFS
                  encData = Mongoid::EncryptedFields.cipher.encrypt(file.read)
                  File.open(file, 'wb') do |f|
                    f.write(encData)
                  end
                  grid_file = grid_fs.put(file.path)
                  pattern.pattern_file_id = grid_file.id
                  Mongoid.override_client(:default)
                else
                  flash[:error] = "Upload must be an rtf/csv"
                end
              else
                pattern = Pattern.new()
                pattern.name = params[:pattern][:name]
                pattern.description = params[:pattern][:description]
                pattern.pattern_type = params[:pattern][:pattern_type]
                pattern.application_id = params[:Application].to_i
                pattern.html_block_id = HtmlBlock.where(:name=>params[:pattern][:html_block_id]).pluck(:id)[0]
              end
              if pattern.save
                respond_to do |format|
                  format.html { redirect_to_on_success }
                  format.js { render json: {id: pattern.id.to_s, label: @model_config.with(object: pattern).object_label} }
                end
              else 
                if params[:pattern][:pattern]
                  if(CaseCenter::Config::Reader.get('mongodb_attachment_database'))
                    Mongoid.override_client(:attachDb)
                  end
                  grid_fs.delete(pattern.pattern_file_id)
                  Mongoid.override_client(:default)
                end
                pattern.errors.full_messages.each do |message|
                  flash[:error] = message
                end
              end
              if params[:pattern][:pattern]
                File.delete(file.path)
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
