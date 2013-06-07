module RailsAdmin

  class MainController < RailsAdmin::ApplicationController
    include ActionView::Helpers::TextHelper

    layout "rails_admin/dashboard"

    before_filter :get_model, :except => [:index, :update_scope, :global_search]
    before_filter :get_object, :only => [:show, :edit, :update, :delete, :destroy, :system_export]
    before_filter :check_scope_on_query, :except => [:index, :update_scope]
    before_filter :get_attributes, :only => [:create, :update]
    before_filter :check_for_cancel, :only => [:create, :update, :destroy, :export, :bulk_destroy]


    def index
      @authorization_adapter.authorize(:index) if @authorization_adapter
      @page_name = t("admin.dashboard.pagename")
      @page_type = "dashboard"

      @history = AbstractHistory.history_latest_summaries(@scope_adapter, @authorization_adapter)
      @month = DateTime.now.month
      @year = DateTime.now.year
      @history= AbstractHistory.history_for_month(@month, @year, @scope_adapter, @authorization_adapter)

      @abstract_models = RailsAdmin::Config.visible_models.map(&:abstract_model)

      @most_recent_changes = {}
      @count = {}
      @max = 0
      @abstract_models.each do |t|
        scope = @authorization_adapter && @authorization_adapter.query(:list, t)
        current_count = t.count({}, scope)
        @max = current_count > @max ? current_count : @max
        @count[t.pretty_name] = current_count
        @most_recent_changes[t.pretty_name] = t.model.order("updated_at desc").first.try(:updated_at) rescue nil
      end
      render :index
    end

    def global_search
      result = []
      RailsAdmin::AbstractModel.all.each do |m|
        @abstract_model = m
        @model_config = RailsAdmin.config(@abstract_model)
        not_found if @model_config.excluded?
        @properties = @abstract_model.properties
        list_entries({}, {})[0].each do |e|
          next if not e.respond_to?(:name)
          result << {
            :label => e.name , :model_name => e.class.model_name, :category => e.class.model_name.human, :url => edit_url(@current_scope_parameters.merge(:id => e.id, :model_name => e.class.model_name))
          }
        end
      end
      render :json => result
    end

    def list
      @authorization_adapter.authorize(:list, @abstract_model) if @authorization_adapter

      @page_type = @abstract_model.pretty_name.downcase
      @page_name = t("admin.list.select", :name => @model_config.label.downcase)

      @objects, @current_page, @page_count, @record_count = list_entries
      @schema ||= { :only => @model_config.list.visible_fields.map {|f| f.name } }

      respond_to do |format|
        format.html{
          if @abstract_model.model.name == "Ckeditor::Asset" then
            @iframe_url = "/ckeditor/pictures?CKEditorFuncNum=2&mode=standalone&assetable_id=#{params[:Company]}&assetable_type=Company"
            render "iframe"
          end
        }
        format.js { render :layout => 'rails_admin/plain.html.erb' }
        format.json do
          output = if params[:compact]
                     @objects.map{ |o| { :id => o.id, :label => o.send(@model_config.object_label_method) } }
                   else
                     @objects.to_json(@schema)
                   end
          if params[:send_data]
            send_data output, :filename => "#{params[:model_name]} #{DateTime.now.strftime("%Y-%m-%d %H:%M:%S")}.json"
          else
            render :json => output
          end
        end
        format.xml do
          output = @objects.to_xml(@schema)
          if params[:send_data]
            send_data output, :filename => "#{params[:model_name]} #{DateTime.now.strftime("%Y-%m-%d %H:%M:%S")}.xml"
          else
            render :xml => output
          end
        end
        format.csv do
          header, encoding, output = CSVConverter.new(@objects, @schema).to_csv(params[:csv_options])
          if params[:send_data]
            send_data output,
                      :type => "text/csv; charset=#{encoding}; #{"header=present" if header}",
                      :disposition => "attachment; filename=#{params[:model_name]} #{DateTime.now.strftime("%Y-%m-%d %H:%M:%S")}.csv"
          else
            render :text => output
          end
        end
      end
    end

    def new
      @object = @abstract_model.new
      if @authorization_adapter
        @authorization_adapter.attributes_for(:new, @abstract_model).each do |name, value|
          @object.send("#{name}=", value)
        end
        @authorization_adapter.authorize(:new, @abstract_model, @object)
      end
      if object_params = params[@abstract_model.to_param]
        @object.set_attributes(@object.attributes.merge(object_params), _attr_accessible_role)
      end
      @page_name = t("admin.actions.create").capitalize + " " + @model_config.label.downcase
      @page_type = @abstract_model.pretty_name.downcase
      respond_to do |format|
        format.html
        format.js   { render :layout => 'rails_admin/plain.html.erb' }
      end
    end

    def create
      @modified_assoc = []
      @object = @abstract_model.new
      @model_config.create.fields.each {|f| f.parse_input(@attributes) if f.respond_to?(:parse_input) }
      if @authorization_adapter
        @authorization_adapter.attributes_for(:create, @abstract_model).each do |name, value|
          @object.send("#{name}=", value)
        end
        @authorization_adapter.authorize(:create, @abstract_model, @object)
      end
      @object.set_attributes(@attributes, _attr_accessible_role)
      @page_name = t("admin.actions.create").capitalize + " " + @model_config.label.downcase
      @page_type = @abstract_model.pretty_name.downcase

      if @object.save
        AbstractHistory.create_history_item("Created #{@model_config.with(:object => @object).object_label}", @object, @abstract_model, _current_user)
        respond_to do |format|
          format.html do
            redirect_to_on_success
          end
          format.js do
            render :json => {
                :id => @object.id,
                :label => @model_config.with(:object => @object).object_label,
            }
          end
        end
      else
        handle_save_error
      end
    end

    def show
      @authorization_adapter.authorize(:show, @abstract_model, @object) if @authorization_adapter
      @page_name = t("admin.show.page_name", :name => @model_config.label.downcase)
      @page_type = @abstract_model.pretty_name.downcase
      flash[:error] = "You are in view mode. No change will be saved."
    end

    def edit
      @authorization_adapter.authorize(:edit, @abstract_model, @object) if @authorization_adapter
      @page_name = t("admin.actions.update").capitalize + " " + @model_config.abstract_model.pretty_name.downcase
      @page_type = @abstract_model.pretty_name.downcase

      respond_to do |format|
        format.html { render :layout => 'rails_admin/form' }
        format.js   { render :layout => 'rails_admin/plain.html.erb' }
      end
    end

    def update
      @authorization_adapter.authorize(:update, @abstract_model, @object) if @authorization_adapter

      @cached_assocations_hash = associations_hash
      @modified_assoc = []

      @page_name = t("admin.actions.update").capitalize + " " + @model_config.abstract_model.pretty_name.downcase
      @page_type = @abstract_model.pretty_name.downcase

      @old_object = @object.dup

      @model_config.update.fields.map {|f| f.parse_input(@attributes) if f.respond_to?(:parse_input) }

      @object.set_attributes(@attributes, _attr_accessible_role)

      if @object.save
        object_label = @model_config.with(:object => @object).object_label
        AbstractHistory.create_update_history @abstract_model, @object, @cached_assocations_hash, associations_hash, @modified_assoc, @old_object, _current_user
        respond_to do |format|
          format.html do
            redirect_to_on_success
          end
          format.js do
            render :json => {
                :id => @object.id,
                :label => @model_config.with(:object => @object).object_label,
            }
          end
        end
      else
        handle_save_error :edit
      end
    end

    def delete
      @authorization_adapter.authorize(:delete, @abstract_model, @object) if @authorization_adapter

      @page_name = t("admin.actions.delete").capitalize + " " + @model_config.label.downcase
      @page_type = @abstract_model.pretty_name.downcase

      respond_to do |format|
        format.html { render :layout => 'rails_admin/form' }
        format.js   { render :layout => 'rails_admin/plain.html.erb' }
      end
    end

    def destroy
      @authorization_adapter.authorize(:destroy, @abstract_model, @object) if @authorization_adapter

      if @object.destroy
        AbstractHistory.create_history_item("Destroyed #{@model_config.with(:object => @object).object_label}", @object, @abstract_model, _current_user)
        flash[:notice] = t("admin.flash.successful", :name => @model_config.label, :action => t("admin.actions.deleted"))
      else
        flash[:error] = t("admin.flash.error", :name => @model_config.label, :action => t("admin.actions.deleted"))
      end

      respond_to do |format|
        format.js {render :json => {}}
        format.any {redirect_to list_path(@current_scope_parameters.merge(:model_name => @abstract_model.to_param))}
      end
    end

    def system_export
      mode = params["mode"] rescue nil
      @application = ::Application.find(params['id'])
      @company = ::Company.find(@application.company_id)
      @model_name = params['model_name']

      if mode.nil?
        @object = @abstract_model.new #we do not have an object yet, so create one
        @page_name = t("admin.actions.system_export").capitalize
        @page_type = t("admin.actions.system_export").capitalize

        respond_to do |format|
          format.html { render :layout => 'rails_admin/form' }
          format.js   { render :layout => 'rails_admin/plain.html.erb' }
        end
      elsif mode == 'build'
        begin
          target = Tempfile.new('cc')
          target.close
          CaseCenter::ImportExport.new.export(@company.key, @application.key, target.path)
          Rails.cache.delete(:export_temporary_file)

          File.open(target.path, "rb") do |f|
            Rails.cache.write(:export_temporary_file, Base64.encode64(f.read), :expires_in => 1.minutes)
          end
        rescue Exception => e
          Rails.logger.error("Error while exporting #{e.message}")
          Rails.logger.debug("#{e.backtrace.join('\n')}")
          @error =  e.message
        ensure
          target.unlink unless target.nil?
        end
        render :template => 'rails_admin/main/system_export_download', :layout => nil
      elsif mode == 'download'
          temp_file = Rails.cache.fetch(:export_temporary_file)

          if temp_file.nil?
            Rails.logger.error("Export file download request - file was missing from cache")
            render :text =>"Export file has expired", :status => 500
          else
            send_data Base64.decode64(temp_file),
                    :filename => "#{@company.key}_#{@application.key}_#{Time.now.strftime('%Y%m%d')}.zip",
                    :type => "application/zip"
          end
      end
    end

    def system_import
      #@authorization_adapter.authorize(:system_import, @abstract_model, @object) if @authorization_adapter
      mode = params["mode"] rescue nil
      @model_name = params[:model_name]
      if mode.nil?
        @object = @abstract_model. new #we do not have an object yet, so create one
        @page_name = t("admin.actions.system_import").capitalize
        @page_type = t("admin.actions.system_import").capitalize

        respond_to do |format|
          format.html { render :layout => 'rails_admin/form' }
          format.js   { render :layout => 'rails_admin/plain.html.erb' }
        end
      elsif mode == "upload_iframe"
        render :template => 'rails_admin/main/upload_file_form', :layout => nil
      elsif mode == "upload_file"
        begin
          if Rails.cache.exist?(:import_in_progress)
            raise Exception.new("Another import is currently in progress, please try again later.")
          end

          @import_details = CaseCenter::ImportExport.new.get_company_and_application(params["import_file"].tempfile.path)
          Rails.cache.write(:import_temporary_file, Base64.encode64(params["import_file"].read), :expires_in => 5.minutes)
        rescue Exception => e
          Rails.logger.error("Error while importing #{e.message}")
          Rails.logger.debug("#{e.backtrace.join('\n')}")
          @error =  e.message
        end
        render :template => 'rails_admin/main/upload_file_complete', :layout => nil
      elsif mode == "install_import"
        begin
          @details = {
            :application_name => params['application_name'],
            :application_key => params['application_key']
          }

          if current_user.is_root?
            @details[:company_key] = params['company_key']
            @details[:company_name] = params['company_name']
          else
            if current_user.is_admin?
              @company = ::Company.find(@current_user.company_id)

              if(@company.key != params['company_key'])
                raise Exception.new("You do not have permission to update a company other than #{@company.name}, please try again as a root user")
              end

              @details[:company_key] = @company.key
              @details[:company_name] = @company.name
            else
              raise Exception.new("The current user doesn't have permission to import systems")
            end
          end

          if Rails.cache.exist?(:import_in_progress)
            raise Exception.new("An import is already in progress, please try again later")
          end

          in_file = Rails.cache.fetch(:import_temporary_file)
          if in_file.nil?
            raise Exception.new("The import file has expired, or a duplicate request has been please try you import again")
          end

          Thread.new(@details, Base64.decode64(in_file)) do |details, file_data|
            f = Tempfile.new('cc')
            begin
              Rails.cache.write(:import_in_progress, true)
              Rails.cache.delete(:import_last_error)

              f.binmode
              f.write(file_data)
              f.close()

              CaseCenter::ImportExport.new.import(f.path, details)
              company = ::Company.where(:key => details[:company_key]).first
              application = ::Application.where(:key => details[:application_key]).where(:company_id => company.id).first
              application.generate_mongoid_model(true)
              Rails.cache.write(:import_company_data, {
                  :company_name => company.name,
                  :company_id => company.id,
                  :application_name => application.name,
                  :application_id => application.id,
                })
            rescue Exception => e
              Rails.logger.error("Error while importing #{e.message}")
              Rails.cache.write(:import_last_error, "Error while importing #{e.message}")
            ensure
              Rails.cache.delete(:import_in_progress)
              f.unlink() unless f.nil?
            end
          end

        rescue Exception => e
          Rails.logger.error("Error while importing #{e.message}")
          Rails.logger.debug("#{e.backtrace.join('\n')}")
          @error =  e.message
        end
        render :template => 'rails_admin/main/system_import_complete', :layout => nil
      elsif mode == "check_complete"
        json = {}
        if Rails.cache.exist?(:import_in_progress)
          json[:status] = "In Progress" 
          json[:error] = false
        else
          if Rails.cache.exist?(:import_last_error)
            json[:status] = "Import Error"
            json[:error] = true
            json[:error_description] = Rails.cache.fetch(:import_last_error)
          else
            json[:status] = "Import Complete"
            json[:error] = false
            icd = Rails.cache.fetch(:import_company_data)
            icd.each_pair do |k, v|
              json[k] = v
            end
          end
        end
        render :json => json.to_json
      end

    end

    def export
      # todo
      #   limitation: need to display at least one real attribute ('only') so that the full object doesn't get displayed, a way to fix this? maybe force :only => [""]
      #   use send_file instead of send_data to leverage the x-sendfile header set by rails 3 (generate and let the front server handle the rest)
      # maybe
      #   n-levels (backend: possible with xml&json, frontend: not possible, injections check: quite easy)
      @authorization_adapter.authorize(:export, @abstract_model) if @authorization_adapter

      if format = params[:json] && :json || params[:csv] && :csv || params[:xml] && :xml
        request.format = format
        @schema = params[:schema].symbolize if params[:schema] # to_json and to_xml expect symbols for keys AND values.
        list
      else
        @page_name = t("admin.actions.export").capitalize + " " + @model_config.label.downcase
        @page_type = @abstract_model.pretty_name.downcase

        render :action => 'export'
      end
    end

    def bulk_action
      redirect_to list_path(@current_scope_parameters), :notice => t("admin.flash.noaction") and return if params[:bulk_ids].blank?

      if params.include? :bulk_delete
        bulk_delete
      elsif params.include? :bulk_export
        export
      else
        redirect_to(list_path(@current_scope_parameters.merge(:model_name => @abstract_model.to_param)), :notice => t("admin.flash.noaction"))
      end
    end

    def bulk_delete
      @authorization_adapter.authorize(:bulk_delete, @abstract_model) if @authorization_adapter
      @page_name = t("admin.actions.delete").capitalize + " " + @model_config.label.downcase
      @page_type = @abstract_model.pretty_name.downcase

      @bulk_objects, @current_page, @page_count, @record_count = list_entries

      render :action => 'bulk_delete'
    end

    def bulk_destroy
      @authorization_adapter.authorize(:bulk_destroy, @abstract_model) if @authorization_adapter

      scope = @authorization_adapter && @authorization_adapter.query(params[:action].to_sym, @abstract_model)

      processed_objects = @abstract_model.destroy(params[:bulk_ids], scope)

      destroyed = processed_objects.select(&:destroyed?)
      not_destroyed = processed_objects - destroyed

      destroyed.each do |object|
        message = "Destroyed #{@model_config.with(:object => object).object_label}"
        AbstractHistory.create_history_item(message, object, @abstract_model, _current_user)
      end

      unless destroyed.empty?
        flash[:notice] = t("admin.flash.successful", :name => pluralize(destroyed.count, @model_config.label), :action => t("admin.actions.deleted"))
      end

      unless not_destroyed.empty?
        flash[:error] = t("admin.flash.error", :name => pluralize(not_destroyed.count, @model_config.label), :action => t("admin.actions.deleted"))
      end
      redirect_to list_path(@current_scope_parameters)
    end

    def handle_error(e)
      if RailsAdmin::AuthenticationNotConfigured === e
        Rails.logger.error e.message
        Rails.logger.error e.backtrace.join("\n")

        @error = e
        render 'authentication_not_setup', :status => 401
      else
        super
      end
    end

    def update_scope
      super if @scope_adapter
    end

    private

    def get_bulk_objects(ids)
      scope = @authorization_adapter && @authorization_adapter.query(params[:action].to_sym, @abstract_model)
      objects = @abstract_model.get_bulk(ids, scope)

      not_found unless objects
      objects
    end

    def get_sort_hash
      params[:sort] = params[:sort_reverse] = nil unless @model_config.list.with(:view => self, :object => @abstract_model.model.new).visible_fields.map {|f| f.name.to_s}.include? params[:sort]

      params[:sort] ||= @model_config.list.sort_by.to_s
      params[:sort_reverse] ||= 'false'

      field = @model_config.list.fields.find{ |f| f.name.to_s == params[:sort] }

      column = if field.nil? || field.sortable == true # use params[:sort] on the base table
                 "#{@abstract_model.model.table_name}.#{params[:sort]}"
               elsif field.sortable == false # use default sort, asked field is not sortable
                 "#{@abstract_model.model.table_name}.#{@model_config.list.sort_by.to_s}"
               elsif field.sortable.is_a?(String) && field.sortable.include?('.') # just provide sortable, don't do anything smart
                 field.sortable
               elsif field.sortable.is_a?(Hash) # just join sortable hash, don't do anything smart
                 "#{field.sortable.keys.first}.#{field.sortable.values.first}"
               elsif field.association? # use column on target table
                 "#{field.associated_model_config.abstract_model.model.table_name}.#{field.sortable}"
               else # use described column in the field conf.
                 "#{@abstract_model.model.table_name}.#{field.sortable}"
               end

      reversed_sort = (field ? field.sort_reverse? : @model_config.list.sort_reverse?)
      {:sort => column, :sort_reverse => (params[:sort_reverse] == reversed_sort.to_s)}
    end

    def get_conditions_hash(query, filters)

      # TODO for filtering engine
      #   use a hidden field to store serialized params and send them through post (pagination, export links, show all link, sort links)
      #   Tricky cases where:
      #     query can't be made on any of the avalaible attributes (will it happen a lot Error messages?)
      #     filter can't apply to the targetted attribute (should be sanitized front)
      #   extend engine to :
      #      belongs_to autocomplete id (optionnal)

      #  LATER
      #   find a way for complex request (OR/AND)?
      #   _type should be a dropdown with possible values
      #   belongs_to should be filtering boxes
      #   so that we can create custom engines through the DSL (list.filter = [list of columns])
      #   multiple words queries
      #   find a way to force a column nonetheless?

      # TODO else
      #   searchable & filtering engine
      #   has_one ?
      #   polymorphic ?


      return {} if query.blank? && filters.blank? # perf

      @like_operator =  "ILIKE" if ActiveRecord::Base.configurations[Rails.env]['adapter'] == "postgresql"
      @like_operator ||= "LIKE"

      query_statements = []
      filters_statements = []
      values = []
      conditions = [""]

      if query.present?
        queryable_fields = @model_config.list.fields#.select(&:queryable?)
        queryable_fields.each do |field|
          searchable_columns = field.searchable_columns.flatten
          searchable_columns.each do |field_infos|
            statement, *value = build_statement(field_infos[:column], field_infos[:type], query, field.search_operator)
            if statement && value
              query_statements << statement
              values << value
            end
          end
        end
      end

      unless query_statements.empty?
        conditions[0] += " AND " unless conditions == [""]
        conditions[0] += "(#{query_statements.join(" OR ")})"  # any column field will do
      end

      if filters.present?
        @filterable_fields = @model_config.list.fields.select(&:filterable?).inject({}){ |memo, field| memo[field.name.to_sym] = field.searchable_columns; memo }
        filters.each_pair do |field_name, filters_dump|
          filters_dump.each do |filter_index, filter_dump|
            field_statements = []
            @filterable_fields[field_name.to_sym].each do |field_infos|
              unless filter_dump[:disabled]
                statement, *value = build_statement(field_infos[:column], field_infos[:type], filter_dump[:value], (filter_dump[:operator] || 'default'))
                if statement
                  field_statements << statement
                  values << value
                end
              end
            end
            filters_statements << "(#{field_statements.join(' OR ')})" unless field_statements.empty?
          end
        end
      end

      unless filters_statements.empty?
        conditions[0] += " AND " unless conditions == [""]
        conditions[0] += "#{filters_statements.join(" AND ")}" # filters should all be true
      end

      conditions += values.flatten
      conditions != [""] ? { :conditions => conditions } : {}
    end

    def build_statement(column, type, value, operator)

      # this operator/value has been discarded (but kept in the dom to override the one stored in the various links of the page)
      return if operator == '_discard' || value == '_discard'

      # filtering data with unary operator, not type dependent
      if operator == '_blank' || value == '_blank'
        return ["(#{column} IS NULL OR #{column} = '')"]
      elsif operator == '_present' || value == '_present'
        return ["(#{column} IS NOT NULL AND #{column} != '')"]
      elsif operator == '_null' || value == '_null'
        return ["(#{column} IS NULL)"]
      elsif operator == '_not_null' || value == '_not_null'
        return ["(#{column} IS NOT NULL)"]
      elsif operator == '_empty' || value == '_empty'
        return ["(#{column} = '')"]
      elsif operator == '_not_empty' || value == '_not_empty'
        return ["(#{column} != '')"]
      end

      # now we go type specific
      case type
        when :boolean
          return if value.blank?
          ["(#{column} = ?)", ['true', 't', '1'].include?(value)] if ['true', 'false', 't', 'f', '1', '0'].include?(value)
        when :integer, :belongs_to_association
          return if value.blank?
          ["(#{column} = ?)", value.to_i] if value.to_i.to_s == value
        when :string, :text
          return if value.blank?
          value = case operator
                    when 'default', 'like'
                      "%#{value}%"
                    when 'starts_with'
                      "#{value}%"
                    when 'ends_with'
                      "%#{value}"
                    when 'is', '='
                      "#{value}"
                  end
          ["(#{column} #{@like_operator} ?)", value]
        when :datetime, :timestamp, :date
          return unless operator != 'default'
          values = case operator
                     when 'today'
                       [Date.today.beginning_of_day, Date.today.end_of_day]
                     when 'yesterday'
                       [Date.yesterday.beginning_of_day, Date.yesterday.end_of_day]
                     when 'this_week'
                       [Date.today.beginning_of_week.beginning_of_day, Date.today.end_of_week.end_of_day]
                     when 'last_week'
                       [1.week.ago.to_date.beginning_of_week.beginning_of_day, 1.week.ago.to_date.end_of_week.end_of_day]
                     when 'less_than'
                       return if value.blank?
                       [value.to_i.days.ago, DateTime.now]
                     when 'more_than'
                       return if value.blank?
                       [2000.years.ago, value.to_i.days.ago]
                   end
          ["(#{column} BETWEEN ? AND ?)", *values]
        when :enum
          return if value.blank?
          ["(#{column} = ?)", value]
      end
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

    def redirect_to_on_success
      notice = t("admin.flash.successful", :name => @model_config.label, :action => t("admin.actions.#{params[:action]}d"))
      if params[:_add_another]
        redirect_to new_path(@current_scope_parameters), :notice => notice
      elsif params[:_add_edit]
        redirect_to edit_path(@current_scope_parameters.merge(:id => @object.id)), :notice => notice
      else
        redirect_to list_path(@current_scope_parameters), :notice => notice
      end
    end

    def handle_save_error whereto = :new
      action = params[:action]
      flash.now[:error] = t("admin.flash.error", :name => @model_config.label, :action => t("admin.actions.#{action}d"))
      flash.now[:error] += ". #{@object.errors[:base].to_sentence}" unless @object.errors[:base].blank?

      respond_to do |format|
        format.html { render whereto, :status => :not_acceptable }
        format.js   { render whereto, :layout => 'rails_admin/plain.html.erb', :status => :not_acceptable  }
      end
    end

    def check_for_cancel
      redirect_to list_path(@current_scope_parameters), :notice => t("admin.flash.noaction") if params[:_continue]
    end

    def list_entries(other = {}, options = nil)
      return [get_bulk_objects(params[:bulk_ids]), 1, 1, "unknown"] if params[:bulk_ids].present?

      associations = @model_config.list.fields.select {|f| f.type == :belongs_to_association && !f.polymorphic? }.map {|f| f.association[:name] }

      if !options
        options = get_sort_hash.merge(get_conditions_hash(params[:query], params[:filters])).merge(other).merge(associations.empty? ? {} : { :include => associations })
      else
        options = get_conditions_hash(params[:query], params[:filters])
      end

      scope = @authorization_adapter && @authorization_adapter.query(:list, @abstract_model)
      scope = @scope_adapter.apply_scope(scope, @abstract_model) if @scope_adapter

      current_page = (params[:page] || 1).to_i

      if params[:all]
        objects = @abstract_model.all(options, scope)
        page_count = 1
        record_count = objects.count
      else
        options.merge!(:page => current_page, :per_page => @model_config.list.items_per_page)
        page_count, objects = @abstract_model.paginated(options, scope)
        options.delete(:page)
        options.delete(:per_page)
        options.delete(:offset)
        options.delete(:limit)
        record_count = @abstract_model.count(options, scope)
      end
      [objects, current_page, page_count, record_count]
    end

    def associations_hash
      associations = {}
      @abstract_model.associations.each do |association|
        if [:has_many, :has_and_belongs_to_many].include?(association[:type])
          records = Array(@object.send(association[:name]))
          associations[association[:name]] = records.collect(&:id)
        end
      end
      associations
    end

  end
end
