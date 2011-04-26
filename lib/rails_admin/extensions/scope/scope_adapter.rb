module RailsAdmin
  module Extensions
    module Scope
      # This adapter is for the CanCan[https://github.com/ryanb/cancan] authorization library.
      # You can create another adapter for different authorization behavior, just be certain it
      # responds to each of the public methods here.
      class ScopeAdapter
        # See the +authorize_with+ config method for where the initialization happens.
        def initialize(controller, models = [])
          @models = models
          @controller = controller
          @controller.extend ControllerExtension
        end
        
        def models
          @models
        end  
        
        module ControllerExtension
          def current_scope
            # use _current_user instead of default current_user so it works with
            # whatever current user method is defined with RailsAdmin
            session[:scope] ||= {}
            @current_scope = session[:scope]
          end
          
          def list_entries_for(model_name, association = {})
            abstract_model = RailsAdmin::AbstractModel.new(model_name)
            scope = @authorization_adapter && @authorization_adapter.query(:list, abstract_model)
            abstract_model.where(association, scope)
          end
          
          def get_scope_models
            @scope = {}
            parent_model     = nil
            parent_selection = nil
            @scope_adapter.models.each do |model|
              model_name = model.name
              session[model_name] ||= model.first.id
              association = parent_model && parent_selection ? {"#{parent_model.table_name.singularize}_id" => parent_selection} : parent_model.first.id rescue nil || {}
              @scope[model_name] = {:entries => list_entries_for(model_name, association), :selected => session[model_name] };
              parent_model = model        
              parent_selection = session[model_name]
            end
            p @scope
          end
          
        end
      end
    end
  end
end
