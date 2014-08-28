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

        # Apply the scope to an ActiveRelation object
        # First argument is the query the scope has to be applied to
        # Second argument is the base_model that is used in the select statement.
        # Example: select field from table (table is the base_model).
        def apply_scope(query, base_abstract_model)
          join, tree = nil

          #Treat the User model as a special case since we want to see all the users if they are not hierarchically
          #assigned (ex: User not being associated to a company)
          # if @controller.current_user.class.name == base_abstract_model.model.name then
          #   return query if !@authorization_adapter || @authorization_adapter.authorized?(:list, nil, @controller.current_user.class.name)
          # end        

          @controller.current_scope.each do |key, value|
            next if base_abstract_model.model.name == key

            tree = retrieve_associations_tree(base_abstract_model, key)

            next if not tree

            join = generate_join_query(key, tree[base_abstract_model.model.name])

            query = query.includes(join)

            tree = extract_all_tables(join)

            #build the conditions based on the selected scope
            predicate     = []
            predicate_or  = []
            predicate_and = []

            if(tree.collect{|model| model.to_s.classify}.include?(key))
              predicate << {key.constantize.table_name.to_sym => {:id => value[:selected]}}
            end
            base_abstract_model.belongs_to_associations.each do |assoc|
              next if not assoc[:parent_model].respond_to? :name
              if(@controller.current_scope.include?(assoc[:parent_model].name)) then
                predicate_and << ({assoc[:child_key].to_s => @controller.current_scope[assoc[:parent_model].name][:selected]})
              else
                predicate_or << ({assoc[:child_key].to_s => nil})
              end
            end

            predicate = predicate.inject(:&)
            predicate |= (predicate_or.inject(:|) & predicate_and.inject(:&)) if predicate_or.present? && predicate_and.present?
            query = query.where(predicate)
          end
          query
        end

        #if the current user is root and the table is user we do not want to apply the scope
        #because the root user should see all users everytime.
        def is_root_managing_users?(abstract_model)
          return true if @controller.current_user.is_root? and abstract_model.model.name == 'User'
          return false
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
        # Ex: let's assume a model is defined as followed :
        # Field belongs_to Table belongs_to Company
        # The tree will return [Field, Table, Company]
        # We only return one association relevant to the current scope model
        #
        def retrieve_associations_tree(abstract_model, association_name)
          tree = {}
          current_association_name   = abstract_model.model.name
          current_model_associations = {current_association_name => []}
          abstract_model.belongs_to_associations.each do |assoc|
            next if not assoc[:parent_model].respond_to? :name
            current_abstract_model = RailsAdmin::AbstractModel.new(assoc[:parent_model].name)
            if not check_associations(current_abstract_model)
              current_model_associations[current_association_name] << current_abstract_model.model.name
            else
              current_model_associations[current_association_name] << retrieve_associations_tree(current_abstract_model, current_abstract_model.model.name)
            end
          end
          current_model_associations
        end

        def extract_all_tables(associations, keys = [])
          h = associations
          if  associations.is_a? Array then
            return associations if not associations.first.is_a?(Hash)
            h = associations.first
          end
          keys = keys || []
          h.each do |k, v|
            keys << k
            if v.is_a?(Array) and v.size > 0
              extract_all_tables(v.first, keys)
            elsif v.is_a?(Hash)
              extract_all_tables(v, keys)
            elsif v.is_a?(Symbol)
              keys << v
            end
          end
          keys
        end

        def generate_join_query(scope_model_name, associations_tree)
          associations_tree.each do |sub_association_tree|
            tree = extract_all_tables(sub_association_tree)
            if tree.include?(scope_model_name) then
              return [tree.collect{|model| model.tableize.singularize.to_sym}.reverse.inject { |a, b| {b => a}}]
            end
          end
          return {}
        end

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
            @current_scope = {}
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