module RailsAdmin
  class MainController < RailsAdmin::ApplicationController
    include ActionView::Helpers::TextHelper
    include RailsAdmin::MainHelper
    include RailsAdmin::ApplicationHelper
    include RailsAdmin::Extensions::Scope

    layout :get_layout

    before_filter :get_model, except: [:update_scope, :dashboard, :global_search]
    before_filter :get_object, only: RailsAdmin::Config::Actions.all(:member).collect(&:action_name)
    before_filter :check_scope_on_query, :except => [:index, :update_scope, :dashboard, :global_search]
    before_filter :get_attributes, :only => [:create, :update]
    before_filter :check_for_cancel

  RailsAdmin::Config::Actions.all.each do |action|
      class_eval <<-EOS, __FILE__, __LINE__ + 1
        def #{action.action_name}
          action = RailsAdmin::Config::Actions.find('#{action.action_name}'.to_sym)
          @authorization_adapter.try(:authorize, action.authorization_key, @abstract_model, @object)
          @action = action.with({controller: self, abstract_model: @abstract_model, object: @object})
          fail(ActionNotAllowed) unless @action.enabled?
          @page_name = wording_for(:title)

          instance_eval &@action.controller
        end
      EOS
    end

    def update_scope
      super if @scope_adapter
    end

    def import_attachments
      s3 = Aws::S3::Resource.new(
        access_key_id: CaseCenter::Config::Reader.get("aws_access_key_id"), 
        secret_access_key: CaseCenter::Config::Reader.get("aws_secret_key"), 
        region: "eu-west-2")
      bucketName = CaseCenter::Config::Reader.get("s3_assets_bucket")
      bucket = s3.bucket(bucketName)
      compId = @company.id
      pref = "ckeditor_assets/attachments/"+@company.key
      bucketObjects = bucket.objects(prefix: "#{pref}").collect(&:key)
      result = ActiveRecord::Base.connection.exec_query("SELECT data_file_name, assetable_type from ckeditor_assets where type = 'Ckeditor::AttachmentFile' and assetable_id = #{compId}")
      mySqlNames = result.to_a.map{|myItem|myItem["data_file_name"]}
      bucketObjects.each do |b|
        splitB = b.split('/')[-1]
        normalizedB = splitB.downcase.tr(" ", "_")
        if mySqlNames.include?(normalizedB)
          result.rows.each do |row|
            if row[0] == normalizedB
              @recordId = row[1]
              @records = @application.get_mongoid_class.find_by(id: @recordId) rescue nil
            end
          end
          fileDownloaded = s3.bucket(bucketName).object("#{b}")
          fileDownloaded.get(response_target: "#{Rails.root}/tmp/#{normalizedB}")
          @newAsset = Attachment.new
          attFile = File.open("#{Rails.root}/tmp/#{normalizedB}")
          currentFileType = Terrapin::CommandLine.new('file', '-b --mime-type :file').run(file: attFile.path).strip
          if(CaseCenter::Config::Reader.get('mongodb_attachment_database'))
            Mongoid.override_client(:attachDb)
          end
          grid_fs = Mongoid::GridFS
          encFile = File.open(attFile)
          encData = Mongoid::EncryptedFields.cipher.encrypt(encFile.read)
          File.open(encFile, 'wb') do |f|
            f.write(encData)
          end
          grid_file = grid_fs.put(attFile.path)
          @newAsset.data = grid_file.id #Attachment.data is equal to the BSON::ObjectId of the GridFs file.
          @newAsset.assetable_id = @records.system.company_id

          @newAsset.assetable_type = @recordId
          @newAsset.data_file_name = normalizedB
          @newAsset.user = current_user.email

          @newAsset.data_file_size = File.size(attFile.path).to_i
          @newAsset.updated_at = Time.now.strftime("%a %b %e %Y, %k:%M:%S")
          attFile.close
          if(CaseCenter::Config::Reader.get('mongodb_attachment_database'))
            Mongoid.override_client(:default)
          end
          @newAsset.save!
          begin
            @unique_id = @newAsset.id.to_s
          rescue Exception => e
            @newAsset.destroy
            raise e
          ensure
            count = Attachment.where(:assetable_type => @recordId).size
            @records.system.update_attributes(
              attachments_count: count,
              edited_by: current_user.email,
              edited_by_role: current_user.roles.map(&:name)
            )
          end
        end
      end
      redirect_to "/admin/Company/"+@company.id.to_s+"/edit?locale=en"
    end

    def import_assets
      s3 = Aws::S3::Resource.new(
        access_key_id: CaseCenter::Config::Reader.get("aws_access_key_id"), 
        secret_access_key: CaseCenter::Config::Reader.get("aws_secret_key"), 
        region: "eu-west-2")
      bucketName = CaseCenter::Config::Reader.get("s3_assets_bucket")
      bucket = s3.bucket(bucketName)
      compId = @company.id
      pref = "ckeditor_assets/pictures/"+@company.key
      bucketObjects = bucket.objects(prefix: "#{pref}").collect(&:key)
      result = ActiveRecord::Base.connection.exec_query("SELECT data_file_name from ckeditor_assets where type = 'Ckeditor::Picture' and assetable_id = #{compId}")
      mySqlNames = result.to_a.map{|myItem|myItem["data_file_name"]}
      bucketObjects.each do |b|
        splitB = b.split('/')[-1]
        normalizedB = splitB.downcase.tr(" ", "_")
        if mySqlNames.include?(normalizedB)
          fileDownloaded = s3.bucket(bucketName).object("#{b}")
          fileDownloaded.get(response_target: "#{Rails.root}/tmp/#{normalizedB}")
          file = File.open("#{Rails.root}/tmp/#{normalizedB}")
          picture_asset = PictureAsset.new
          picture_asset.data_file_name = normalizedB
          picture_asset.data_content_type = MIME::Types.type_for("#{Rails.root}/tmp/#{normalizedB}").first.content_type
          if(["image/png", "image/jpeg", "image/jpg", "image/gif", "image/tiff"].include? picture_asset.data_content_type)
            if(CaseCenter::Config::Reader.get('mongodb_attachment_database'))
              Mongoid.override_client(:attachDb)
            end
            grid_fs = Mongoid::GridFS
            thumbFilename = "#{Rails.root}/tmp/thumb"+"#{normalizedB}"
            line = Terrapin::CommandLine.new("convert", ":in -scale :resolution :out")
            line.run(in: file.path, resolution: "30x30", out: thumbFilename)
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
            picture_asset.data_file_size = File.size(file).to_i
            picture_asset.assetable_id = @company.id.to_i
            picture_asset.image_id = grid_file.id
            grid_thumb_file = grid_fs.put(thumbFile.path)
            picture_asset.thumb_image_id = grid_thumb_file.id
            File.delete(thumbFile.path)
            File.delete(file.path)
            if(CaseCenter::Config::Reader.get('mongodb_attachment_database'))
              Mongoid.override_client(:default)
            end
            if picture_asset.save
            else
              grid_fs.delete(picture_asset.image_id)
              grid_fs.delete(picture_asset.thumb_image_id)
              picture_asset.errors.full_messages.each do |message|
                flash[:error] = message
              end
            end
          else
            flash[:error] = "Upload must be an image"
          end
        end
      end
      redirect_to "/admin/picture_asset"
    end

    def bulk_action
      send(params[:bulk_action]) if params[:bulk_action].in?(RailsAdmin::Config::Actions.all(controller: self, abstract_model: @abstract_model).select(&:bulkable?).collect(&:route_fragment))
    end

    def global_search
      result = []
      RailsAdmin.config.included_models.each do |m|
        cached = Rails.cache.fetch(Digest::SHA1.hexdigest("admin/global_search/#{current_ability.cache_key}/#{params[:query]}/#{@current_scope_parameters.to_s}/#{cache_key(m)}")) do
          model_result = []
        @model_config=RailsAdmin.config(m)
        list_entries(@model_config).each do |e|
          if e.respond_to?(:name)
            model_result << {
                :label => e.name , :class => Common::MENU_LIST[e.class.model_name.to_s], :model_name => e.class.model_name.to_s, :category => e.class.model_name.human, :url => edit_url(@current_scope_parameters.merge(:id => e.id, :model_name => e.class.model_name))
            }
          end
        end
        model_result
      end
      result.concat cached
      end

      render :json => result
    end
   
    def list_entries(model_config = @model_config, auth_scope_key = :index, additional_scope = get_association_scope_from_params, pagination = !(params[:associated_collection] || params[:all] || params[:bulk_ids]))
      
      scope = model_config.abstract_model.scoped

      if auth_scope = @authorization_adapter && @authorization_adapter.query(auth_scope_key, model_config.abstract_model)
        scope = scope.merge(auth_scope)
      end
      scope = scope.instance_eval(&additional_scope) if additional_scope
      get_collection(model_config, scope, pagination)

    end

  private

    def get_layout
      "rails_admin/#{request.headers['X-PJAX'] ? 'pjax' : 'application'}"
    end

    def back_or_index
      params[:return_to].presence && params[:return_to].include?(request.host) && (params[:return_to] != request.fullpath) ? params[:return_to] : index_path
    end

    def get_sort_hash(model_config)
      abstract_model = model_config.abstract_model
      params[:sort] = params[:sort_reverse] = nil unless model_config.list.fields.collect { |f| f.name.to_s }.include? params[:sort]
      params[:sort] ||= model_config.list.sort_by.to_s
      params[:sort_reverse] ||= 'false'

      field = model_config.list.fields.detect { |f| f.name.to_s == params[:sort] }
      column = begin
        if field.nil? || field.sortable == true # use params[:sort] on the base table
          "#{abstract_model.table_name}.#{params[:sort]}"
        elsif field.sortable == false # use default sort, asked field is not sortable
          "#{abstract_model.table_name}.#{model_config.list.sort_by}"
        elsif (field.sortable.is_a?(String) || field.sortable.is_a?(Symbol)) && field.sortable.to_s.include?('.') # just provide sortable, don't do anything smart
          field.sortable
        elsif field.sortable.is_a?(Hash) # just join sortable hash, don't do anything smart
          "#{field.sortable.keys.first}.#{field.sortable.values.first}"
        elsif field.association? # use column on target table
          "#{field.associated_model_config.abstract_model.table_name}.#{field.sortable}"
        else # use described column in the field conf.
          "#{abstract_model.table_name}.#{field.sortable}"
        end
      end

      reversed_sort = (field ? field.sort_reverse? : model_config.list.sort_reverse?)
      {sort: column, sort_reverse: (params[:sort_reverse] == reversed_sort.to_s)}
    end

    def redirect_to_on_success      
      notice = t('admin.flash.successful', name: @model_config.label, action: t("admin.actions.#{@action.key}.done"))
      if params[:_add_another]
        redirect_to new_path(@current_scope_parameters.merge(return_to: params[:return_to])), flash: {success: notice}
      elsif params[:_add_edit]
        redirect_to edit_path(@current_scope_parameters.merge(id: @object.id, return_to: params[:return_to])), flash: {success: notice}
      elsif ( ["Application", "Company"].include? @abstract_model.model_name  and  params[:action] == "new"  )        
        redirect_to new_company_or_application_path, flash: {success: notice}
      elsif ( !["Application", "Company"].include? @abstract_model.model_name  and  params[:action] == "new"  )  
        redirect_to index_path, flash: {success: notice}
      else
        redirect_to back_or_index, flash: {success: notice}
      end
    end

    def new_company_or_application_path
      if @abstract_model.model_name == "Application" 
        "/admin?Company=#{@current_scope_parameters["Company"]}&Application=#{@object.id.to_s}&locale=#{params["locale"]}"
      elsif @abstract_model.model_name == "Company" 
        "/admin?Company=#{@object.id.to_s}&Application=#{@current_scope_parameters["Application"]}&locale=#{params["locale"]}"
      end
    end

    def visible_fields(action, model_config = @model_config)
      model_config.send(action).with(controller: self, view: view_context, object: @object).visible_fields
    end

    def sanitize_params_for!(action, model_config = @model_config, target_params = params[@abstract_model.param_key])
      return unless target_params.present?
      fields = visible_fields(action, model_config)
      allowed_methods = fields.collect(&:allowed_methods).flatten.uniq.collect(&:to_s) << 'id' << '_destroy'
      fields.each { |field|  field.parse_input(target_params) }
      target_params.slice!(*allowed_methods)
      target_params.permit! if target_params.respond_to?(:permit!)
      fields.select(&:nested_form).each do |association|
        children_params = association.multiple? ? target_params[association.method_name].try(:values) : [target_params[association.method_name]].compact
        (children_params || []).each do |children_param|
          sanitize_params_for!(:nested, association.associated_model_config, children_param)
        end
      end
    end

    def handle_save_error(whereto = :new)
      flash.now[:error] = t('admin.flash.error', name: @model_config.label, action: t("admin.actions.#{@action.key}.done").html_safe).html_safe
      flash.now[:error] += %(<br>- #{@object.errors.full_messages.join('<br>- ')}).html_safe

      respond_to do |format|
        format.html { render whereto, status: :not_acceptable }
        format.js   { render whereto, layout: false, status: :not_acceptable  }
      end
    end

    def check_for_cancel
      return unless params[:_continue] || (params[:bulk_action] && !params[:bulk_ids])
      redirect_to(back_or_index, notice: t('admin.flash.noaction'))
    end

    def get_collection(model_config, scope, pagination)
      associations = model_config.list.fields.select { |f| f.type == :belongs_to_association && !f.polymorphic? }.collect { |f| f.association.name }
      options = {}
      options = options.merge(page: (params[Kaminari.config.param_name] || 1).to_i, per: (params[:per] || model_config.list.items_per_page)) if pagination
      options = options.merge(include: associations) unless associations.blank?
      options = options.merge(get_sort_hash(model_config))
      options = options.merge(query: params[:query]) if params[:query].present?
      options = options.merge(filters: params[:f]) if params[:f].present?
      options = options.merge(bulk_ids: params[:bulk_ids]) if params[:bulk_ids]
      model_config.abstract_model.all(options, scope)
    end

    def get_association_scope_from_params
      return nil unless params[:associated_collection].present?
      source_abstract_model = RailsAdmin::AbstractModel.new_new(to_model_name(params[:source_abstract_model]))
      source_model_config = source_abstract_model.config
      source_object = source_abstract_model.get(params[:source_object_id])
      action = params[:current_action].in?(%w(create update)) ? params[:current_action] : 'edit'
      @association = source_model_config.send(action).fields.detect { |f| f.name == params[:associated_collection].to_sym }.with(controller: self, object: source_object)
      @association.associated_collection_scope
    end

    def get_attributes
      @attributes = params[@abstract_model.to_param.singularize.gsub('~','_')] || {}
      @attributes.each do |key, value|
        # Deserialize the attribute if attribute is serialized
        if @abstract_model.model.serialized_attributes.keys.include?(key) and value.is_a? String
          @attributes[key] = YAML::load(value)
        end
        # Delete fields that are blank
        @attributes[key] = nil if value.blank?
      end
    end
  end

end
