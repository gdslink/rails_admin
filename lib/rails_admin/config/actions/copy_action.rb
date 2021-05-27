module RailsAdmin
  module Config
    module Actions
      class CopyAction < RailsAdmin::Config::Actions::Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option :member do
          true
        end

        register_instance_option :controller do
          proc do
            if request.get? # EDIT
              @newObject = @object.dup
              objectNameCopy = @object.name + "_copy_"
              objectNameLength = objectNameCopy.length + 1  
              @queues = Filter.where('name LIKE ? and application_id = ? and length(name) = ?',"%#{objectNameCopy}%", "#{@application.id}", "#{objectNameLength}")
              @queuesKey = Filter.where('`key` LIKE ? and application_id = ? and length(`key`) = ?',"%#{objectNameCopy}%", "#{@application.id}", "#{objectNameLength}")
              
              @allQueues = @queues.concat @queuesKey
              @allQueues.uniq!

              x = 1
              @allQueues.each do |q|
                x=x+1
              end

              if !@allQueues.empty?
                @queueNamesKeys = []
                @queueNumbersOnly = []
                @allQueues.each do |q|
                  @queueNamesKeys.push(q.name, q.key)
                end
                @queueNamesKeys.uniq!
                @queueNamesKeys.each do |q|
                  j = Integer(q[-1]) rescue nil
                  if j.is_a? Integer
                    @queueNumbersOnly.push(q[-1])
                  end
                end
                @queueNumbersOnly = @queueNumbersOnly.sort!
                newNameNumber = @queueNumbersOnly.last.to_i + 1
                @newObject.name = @newObject.name + "_copy_" + newNameNumber.to_s
                @newObject.key = @newObject.key + "_copy_" + newNameNumber.to_s
              else
                @newObject.name = @newObject.name + "_copy_" + x.to_s
                @newObject.key = @newObject.key + "_copy_" + x.to_s
              end

              @object.filter_screen_flows.each do |fsf|
                newFsf = fsf.dup
                @newObject.filter_screen_flows.push(newFsf)
              end
              @newObject.fields = @object.fields
              if @newObject.save
                invalidate_cache_key("Filter")
                @auditing_adapter && @auditing_adapter.create_object(@newObject, @abstract_model, _current_user)
                respond_to do |format|
                  format.html { redirect_to_on_success }
                  format.js { render json: {id: @newObject.id.to_s, label: @model_config.with(object: @newObject).object_label} }
                end
              else
                @newObject.errors.full_messages.each do |message|
                  flash.now[:error] = message
                end
              end
            end
          end
        end

        register_instance_option :link_icon do
          'fa fa-copy'
        end

        register_instance_option :pjax? do
          false
        end

        register_instance_option :visible? do
          is_visible = authorized?
          if !bindings[:controller].current_user.is_root && !bindings[:controller].current_user.is_admin && !bindings[:abstract_model].try(:model_name).nil?
            model_name = bindings[:controller].abstract_model.model_name
            is_visible = (bindings[:controller].current_ability.can? :"asset_action_#{model_name}", bindings[:controller].current_scope["Company"][:selected_record]) && model_name == "PictureAsset"
          end
          is_visible
        end

      end
    end
  end
end
