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
            @all_users = User.all
            @all_properties = UserProperty.all
            @all_roles = Role.all
            if request.get? # EDIT
              respond_to do |format|
                format.html { render @action.template_name }
                format.js   { render @action.template_name, layout: false }
              end

            elsif request.put? # UPDATE
              userObjects = []
              selectedProperties = params.select{|k, v| k =~ /^prop/} #Get all params starting with 'prop'
              userEmails = params[:userEmails].split(',') #split userEmails param into comma seperated list
              userIterator = 0
              userEmails.each{|userEmail| userObjects.push(User.where(email: userEmail))} #Loop over each email, get User object where email = userEmail in userEmails list
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
      end
    end
  end
end
