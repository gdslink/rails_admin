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
          
          #Treat the User model as a special case since we want to see all the users if they are not hierarchically
          #assigned (ex: User not being associated to a company)
          if @controller.current_user.class.name == base_abstract_model.model.name then
            return query if !@authorization_adapter || @authorization_adapter.authorized?(:list, nil, @controller.current_user.class.name)
          end
          
          @controller.current_scope.each do |key, value|
            next if base_abstract_model.model.name == key
            tree = retrieve_associations_tree(base_abstract_model, key)
            next if not tree
            
            #remove the first element since it's always going to be the abstract base model
            tree.shift
            
            #build the joins query
            query = query.includes([tree.collect{|model| model.table_name.singularize.to_sym}.reverse.inject { |a, b| {b => a}}])

            #build the conditions based on the selected scope
            predicate     = []
            predicate_or  = []
            predicate_and = []            
            if(tree.collect{|model| model.name}.include?(key))
              predicate << {key.constantize.table_name.to_sym => {:key => value}}
            end
            base_abstract_model.belongs_to_associations.each do |assoc|
              if(@controller.current_scope.include?(assoc[:parent_model].name)) then
                predicate_and << ({assoc[:child_key][0].to_s => @controller.current_scope[assoc[:parent_model].name]})
              else
                predicate_or << ({assoc[:child_key][0].to_s => nil})
              end
            end            
            
            predicate = predicate.inject(:&)                         
            predicate |= (predicate_or | predicate_and).inject(:&) if predicate_or.length > 0
            query = query.where(predicate)
          end
          query
        end
        
        private
        
        def check_associations(abstract_model, tree = [])
          tree << abstract_model.model.name
          abstract_model.belongs_to_associations.each do |assoc|
            tree << assoc[:parent_model].name     
            check_associations(RailsAdmin::AbstractModel.new(assoc[:parent_model].name))
          end
          
          return (self.models.collect{|m| m.name} & tree).length > 0
        end
        
        # Retrieve the association hierarchy for a model.
        # Ex: let's assume a model is defined as follow :
        # Field belongs_to Table belongs_to Company
        # The tree will return [Field, Table, Company]
        #
        def retrieve_associations_tree(abstract_model, association_name, tree = [])
          tree << abstract_model.model
          abstract_model.belongs_to_associations.each do |assoc|
            abstract_model = RailsAdmin::AbstractModel.new(assoc[:parent_model].name)
            next if not check_associations(abstract_model)
            retrieve_associations_tree(abstract_model, association_name, tree) if not tree.include?(abstract_model.model)
          end
          tree = nil if not tree.include?(association_name.constantize) rescue nil
          tree
        end
                        
        module ControllerExtension
          
          def current_scope
            # use _current_user instead of default current_user so it works with
            # whatever current user method is defined with RailsAdmin
            @current_scope = session[:scope]
          end

          def update_session_for_model(model, object_key)
            session[:scope][model.name] = object_key
          end

          def update_scope
            @scope_adapter.models.each do |model|
              update_session_for_model(model, params[model.name])
            end
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
            begin
              @scope = {}
              session[:scope] ||= {}
              parent_model     = nil
              parent_selection_id = nil
              @scope_adapter.models.each do |model|                
                model_name = model.name
                association = parent_model && parent_selection_id ? {"#{parent_model.table_name.singularize}_id" => parent_selection_id} : parent_entries.first.id rescue nil || {} 
                entries = list_entries_for(model_name, association)
                if(entries.reject{|e| e.key != session[:scope][model_name]}.length == 1)
                  selection = params[model.name] || session[:scope][model_name]
                  update_session_for_model(model, selection)
                else #reset
                  selection = entries.first.key rescue nil
                  update_session_for_model(model, selection)
                end
                id_for_selection = model.find_by_key(selection).id
                @scope[model_name] = {:entries => entries, :selected => selection, :selected_id  => id_for_selection }
                
                #save the parent information so we can cascade reset if needed
                parent_model = model
                parent_entries = entries
                parent_selection_id = id_for_selection
              end
            rescue
              redirect_to rails_admin_dashboard_path
            end
          end
        end
      end
    end
  end
end
