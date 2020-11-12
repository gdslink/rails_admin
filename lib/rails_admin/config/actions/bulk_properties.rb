module RailsAdmin
  module Config
    module Actions
      class BulkProperties < RailsAdmin::Config::Actions::Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option :collection do
          true
        end

        register_instance_option :http_methods do
          [:get, :put]
        end

        register_instance_option :controller do
          proc do
            @all_users = User.where(company_id: @company.id)
            @all_properties = UserProperty.where(company_id: @company.id)
            @all_roles = Role.where(application_id: @application.id)
            if request.get? # EDIT
              respond_to do |format|
                format.html { render @action.template_name }
                format.js   { render @action.template_name, layout: false }
              end

            elsif request.put? # UPDATE
              userObjects = []
              selectedProperties = params.select{|k, v| k =~ /^prop/} #Get all params starting with 'prop'
              userIterator = 0
              if params[:userEmails].include? ""
                params[:userEmails].delete("")
              end
              params[:userEmails].each{|userEmail| userObjects.push(User.where(email: userEmail))} #Loop over each email, get User object where email = userEmail in userEmails list
              bulkedPropAndCheckbox = selectedProperties.each_slice(2).to_a #Split selectedProperties array into the checkbox and property in their own array
              bulkedPropAndCheckbox.each{ |set|  #Loop over each group of checkbox and property
                if set[0][1]=="on" #Check if checkbox is ticked
                  propName = set[1][0]
                  cleanPropName = propName[4..-1]
                  propObject = UserProperty.where(:name => cleanPropName)
                  propKey = propObject.pluck(:key)
                  userObjects.each{ |user| 
                    if UserPropertyValue.exists?(:user_id => user.ids, :key => propKey)
                      foundPropVal = UserPropertyValue.where(:user_id => user.ids, :key => propKey)
                      foundPropVal[0].update(value: set[1][1])
                    else #UserPropertyValue not found
                      newUserPropVal = UserPropertyValue.new
                      newUserPropVal.user_id = user.ids[0]
                      newUserPropVal.key = propKey[0]
                      newUserPropVal.value = set[1][1]
                      newUserPropVal.company_id = params[:Company]
                      newUserPropVal.save
                    end
                  }
                else
                end
              }
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
            is_visible = bindings[:controller].current_ability.can? :"bulk_properties_#{model_name}", bindings[:controller].current_scope["Application"][:selected_record]
          end
          is_visible
        end

      end
    end
  end
end
