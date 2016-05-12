module RailsAdmin
  module Extensions
    module Scope

      # This adapter enables a scope selector that limits the records fetched from the DB
      # to the specified scope.
      class ScopeAdapter

        attr_accessor :current_scope

        # See the +scope_with+ config method for where the initialization happens.
        def initialize(controller, models = [])
          @models = models.map {|m| m.constantize}
          @controller = controller
          @controller.extend ControllerExtension
        end

        # Array of the models defined as part of the scope configuration
        # Ex:
        # RailsAdmin.scope_with :scope, [Company, Application]
        # In this example, models will return [Company, Application]
        #
        def models
          @models
        end

        private


        module ControllerExtension

          def scope_adapter
            @scope_adapter
          end

          def current_scope
            @current_scope
          end

          def update_session_for_model(model, object_id)
            session[:scope][model.name] = object_id
          end

          def update_scope
            @scope_adapter.models.each do |model|
              invalidate_cache_key(model.name)
              update_session_for_model(model, params[model.name])
            end
            get_scope_models

            respond_to do |format|
              #format.html {render :text => "ok"+session[:scope]['Company']}
              format.js {render :partial => 'rails_admin/extensions/scope/scope_selector', :locals => {:models => @scope_adapter.models}}
            end
          end

          def list_entries_for(model_name, association = {})
            Rails.cache.fetch(Digest::SHA1.hexdigest("admin/scope/#{current_ability.cache_key}/#{cache_key(model_name)}/#{association.to_s}")) do
              abstract_model = RailsAdmin::AbstractModel.new(model_name)
              scope = @authorization_adapter && @authorization_adapter.query(:list, abstract_model)
              abstract_model.where(association, scope).entries
            end
          end

          def get_scope_models
            @current_scope  = {}
            session[:scope] ||= {}
            parent_model     = nil
            parent_selection_id = nil
            @scope_adapter.models.each do |model|
              model_name = model.name
              association = parent_model && parent_selection_id ? {"#{parent_model.table_name.singularize}_id" => parent_selection_id} : parent_entries.first.id rescue nil || {}
              entries = list_entries_for(model_name, association)
              if(entries.reject{|e| e.id != session[:scope][model_name].to_i}.length == 1)
                selection = params[model.name] || session[:scope][model_name]
                update_session_for_model(model, selection)
              else #reset
                model_value = current_user.respond_to?(model.name.downcase.to_sym) ? current_user.send(model.name.downcase) : nil
                selection = params[model.name].to_s.length > 0 ? params[model.name] : (model_value || entries.first).id rescue nil
                update_session_for_model(model, selection)
              end

              @current_scope[model_name] = {:entries => entries, :selected  => selection, :selected_record => (entries[entries.index{|e| e.id == selection.to_i}] rescue nil)}

              self.instance_variable_set("@#{model.to_s.underscore}", @current_scope[model_name][:selected_record] )

              #save the parent information so we can cascade reset if needed
              parent_model = model
              parent_entries = entries
              parent_selection_id = selection
            end
            @scope_adapter.current_scope = @current_scope
          end
        end
      end
    end
  end
end