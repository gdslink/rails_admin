module RailsAdmin
  class History < ActiveRecord::Base
    self.table_name = :rails_admin_histories

    IGNORED_ATTRS = Set[:id, :created_at, :created_on, :deleted_at, :updated_at, :updated_on, :deleted_on]

    if defined?(ActiveModel::MassAssignmentSecurity) && ancestors.include?(ActiveModel::MassAssignmentSecurity)
      attr_accessible :message, :item, :table, :username, :application_id
    end

    # default_scope { order('id DESC') }
    default_scope {where(application_id: User.current_user.current_scope['Application']).order('id DESC') unless User.current_user.nil? or User.current_user.current_scope.nil?}

    class << self
      def latest
        if current_query_scope.nil?
          limit(100)
        else
          current_query_scope.limit(100)
        end
      end

      def create_history_item(message, object, abstract_model, user)
        application_id = if abstract_model.to_s == "Company"
                           nil
                         elsif abstract_model.to_s == "Application"
                           object.id
                         else
                           User.current_user.current_scope['Application'] || nil
                         end

        binding.pry 

        if abstract_model.to_s == "PictureAsset"
          create(message: [message].flatten.join(', '),
           item: object.data_file_name,
           table: abstract_model.to_s,
           username: user.try(:email),
           application_id: application_id
          )
          return
        end  
                               
        create(message: [message].flatten.join(', '),
               item: object.id,
               table: abstract_model.to_s,
               username: user.try(:email),
               application_id: application_id
        )
      end

      def history_for_model(abstract_model, query, sort, sort_reverse, all, page, per_page = (RailsAdmin::Config.default_items_per_page || 20))
        history = where(table: abstract_model.to_s)
        history_for_model_or_object(history, abstract_model, query, sort, sort_reverse, all, page, per_page)
      end

      def history_for_object(abstract_model, object, query, sort, sort_reverse, all, page, per_page = (RailsAdmin::Config.default_items_per_page || 20))
        history = where(table: abstract_model.to_s, item: object.id)
        history_for_model_or_object(history, abstract_model, query, sort, sort_reverse, all, page, per_page)
      end

      protected

      def history_for_model_or_object(history, _abstract_model, query, sort, sort_reverse, all, page, per_page)
        history = history.where('message LIKE ? OR username LIKE ?', "%#{query}%", "%#{query}%") if query
        history = history.order(sort_reverse == 'true' ? "#{sort} DESC" : sort) if sort
        all ? history : history.send(Kaminari.config.page_method_name, page.presence || '1').per(per_page)
      end

      def current_query_scope
        if User.current_user && User.current_user.current_scope
          return where(application_id: User.current_user.current_scope['Application']) if !User.current_user.current_scope['Application'].nil?
          return where(item: User.current_user.current_scope['Company'], table: "Company") if !User.current_user.current_scope['Company'].nil?
        end
        nil
      end

    end
  end
end
