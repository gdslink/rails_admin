module RailsAdmin
  module Extensions
    module Scope
      # This adapter enables a scope selector that limits the records fetched from the DB
      # to the specified scope.
      class ScopeAdapter
        # See the +scope_with+ config method for where the initialization happens.
        def initialize(controller, models = [])
          @models = models
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
        
        # Apply the scope to an ActiveRelation object
        # First argument is the query the scope has to be applied to
        # Second argument is the base_model that is used in the select statement.
        # Example: select field from table (table is the base_model).
        def apply_scope(query, base_abstract_model)
          tree = nil
          @controller.current_scope.each do |key, value|
            next if base_abstract_model.model.name == key
            tree = retrieve_associations_tree(base_abstract_model, key)
            next if not tree
            tree.each do |model|
              next if model == base_abstract_model.model
              #we check if the tree has only one association.
              #We check the length against 2 because the first element is always
              #the main model, the next object in the array is the first association etc...
              if tree.length == 2 then
                query = query.where("#{model.table_name.singularize}_id = #{value}")
              else
                case model.name
                when key
                  query = query.where("#{model.table_name.singularize}_id = #{value}")
                else
                  query = query.joins(model.table_name.singularize.to_sym)
                end
              end        
            end
          end
          query
        end
        
        private
        
        # Retrieve the association hierarchy for a model.
        # Ex: let's assume a model is defined as follow :
        # Field belongs_to Table belongs_to Company
        # The tree will return [Field, Table, Company]
        #
        def retrieve_associations_tree(abstract_model, association_name, tree = [])
          tree << abstract_model.model
          abstract_model.associations.each do |assoc|
            abstract_model = RailsAdmin::AbstractModel.new(assoc[:parent_model].name)
            retrieve_associations_tree(abstract_model, association_name, tree) if not tree.include?(abstract_model.model)        
          end
          tree = nil if not tree.include?(association_name.constantize) rescue nil
          tree
        end
                        
        module ControllerExtension
          
          def current_scope
            # use _current_user instead of default current_user so it works with
            # whatever current user method is defined with RailsAdmin
            session[:scope] ||= {}
            @current_scope = session[:scope]
          end
          
          def update_scope
            model = @scope_adapter.models[@scope_adapter.models.index { |model| params[:model] == model.name }]
            session[:scope][model.name] = params[:selected]
            get_scope_models
            respond_to do |format|
              format.js {render :partial => 'rails_admin/extensions/scope/scope_selector', :locals => {:models => @scope_adapter.models}}
            end
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
              session[:scope][model_name] ||= model.first.id
              association = parent_model && parent_selection ? {"#{parent_model.table_name.singularize}_id" => parent_selection} : parent_model.first.id rescue nil || {}
              @scope[model_name] = {:entries => list_entries_for(model_name, association), :selected => session[:scope][model_name] };
              parent_model = model        
              parent_selection = session[:scope][model_name]
            end
          end          
        end
      end
    end
  end
end
