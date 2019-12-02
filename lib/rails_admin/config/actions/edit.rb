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
              @object.set_attributes(params[@abstract_model.param_key])
              @authorization_adapter && @authorization_adapter.attributes_for(:update, @abstract_model).each do |name, value|
                @object.send("#{name}=", value)
              end
              changes = @object.changes
              changes.delete(:authentication_token)
              changes.each { |k,v| changes.delete(k) if v[0] == v[1] }   # delete the attribute from changes hash if old values = new values
              
              if @object.save
                @object.reload
                if @abstract_model.model_name == "Environment"  
                  # handle Environment's schedule values history. apply updates on the temp copies and read changes
                  @object.schedule_values.each_with_index do |obj, i|
                    obj.attributes.keys.each{|attr| old_schedule_values[i][attr] = obj[attr] unless ["created_at", "updated_at"].include? attr }
                    schedule_changes.merge!(old_schedule_values[i].changes)
                    schedule_changes_itemized.merge!(schedule_changes)
                    schedule_changes.each{ |k,v| schedule_changes_itemized[obj.key.to_s + "." + k] =  schedule_changes_itemized.delete k    }
                   end                    
                  changes.merge!(schedule_changes_itemized)

                  # handle Environments property values history. apply updates on the temp copies and read changes
                  @object.environment_property_values.each_with_index do |obj, i|
                    obj.attributes.keys.each{|attr| old_env_property_values[i][attr] = obj[attr] unless ["created_at", "updated_at"].include? attr }
                    env_property_changes.merge!(old_env_property_values[i].changes)
                    env_property_changes_itemized.merge!(env_property_changes)
                    env_property_changes.each{ |k,v| env_property_changes_itemized[obj.key.to_s + "." + k] =  env_property_changes_itemized.delete k    }
                   end     
                  changes.merge!(env_property_changes_itemized)
                end

                if @abstract_model.model_name == "User"  
                  # handle User's property values history. apply updates on the temp copies and read changes
                  @object.reload
                  @object.user_property_values.each_with_index do |obj, i|
                    obj.attributes.keys.each{|attr| old_user_properties_values[i][attr] = obj[attr] unless ["created_at", "updated_at"].include? attr }
                    user_property_changes.merge!(old_user_properties_values[i].changes)
                    user_property_changes_itemized.merge!(user_property_changes)
                    user_property_changes.each{ |k,v| user_property_changes_itemized[obj.key.to_s + "." + k] =  user_property_changes_itemized.delete k }
                   end    
                   changes.merge!(user_property_changes_itemized)
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
