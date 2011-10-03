require 'rails_admin/extensions/scope/scope_adapter'

module RailsAdmin

  # Rails Admin's history API.  All access to history data should go
  # through this module so users can patch it to use other history/audit
  # packages.
  class AbstractHistory

    # Create a history record for an update operation.
    def self.create_update_history(model, object, associations_before, associations_after, modified_associations, old_object, user)
      messages = []

      # determine which fields changed ???
      changed_property_list = []
      properties = model.properties.reject{|property| RailsAdmin::History::IGNORED_ATTRS.include?(property[:name])}

      properties.each do |property|
        property_name = property[:name].to_param
        if old_object.safe_send(property_name) != object.safe_send(property_name)
          changed_property_list << property_name
        end
      end

      model.associations.each do |t|
        assoc = changed_property_list.index(t[:child_key].to_param)
        if assoc
          changed_property_list[assoc] = "associated #{t[:pretty_name]}"
        end
      end

      # Determine if any associations were added or removed
      associations_after.each do |key, current|
        removed_ids = (associations_before[key] - current).map{|m| '#' + m.to_s}
        added_ids = (current - associations_before[key]).map{|m| '#' + m.to_s}
        if removed_ids.any?
          messages << "Removed #{key.to_s.capitalize} #{removed_ids.join(', ')} associations"
        end
        if added_ids.any?
          messages << "Added #{key.to_s.capitalize} #{added_ids.join(', ')} associations"
        end
      end

      modified_associations.uniq.each do |t|
        changed_property_list << "associated #{t}"
      end

      if not changed_property_list.empty?
        messages << "Changed #{changed_property_list.join(", ")}"
      end

      create_history_item(messages, object, model, user) unless messages.empty?
    end

    # Create a history item for any operation.
    def self.create_history_item(message, object, abstract_model, user)
      message = message.join(', ') if message.is_a? Array
      date = Time.now
      RailsAdmin::History.create(
                                 :message => message,
                                 :item => object.id,
                                 :table => abstract_model.model.name,
                                 :username => user ? user.email : "",
                                 :month => date.month,
                                 :year => date.year,
                                 :application_id => (object.application_id rescue nil)
                                 )
    end

    # Fetch the history items for a model.  Returns an array containing
    # the page count and an AR query result containing the history
    # items.

    def self.history_for_model(abstract_model, query, sort, sort_reverse, all, page, scope_adapter,authorization_adapter, per_page=20)
      page ||= "1"

      # apply scope
      scope = authorization_adapter.query(:list, abstract_model)
      scoped_records = scope_adapter.apply_scope(scope, abstract_model)
    
      id_list = Array.new
      scoped_records.each { |record|
        id_list << record.id
      }
      
      history = History.where :table => abstract_model.model.name, :item => id_list

      if query
        history = history.where "#{History.connection.quote_column_name(:message)} LIKE ? OR #{History.connection.quote_column_name(:username)} LIKE ?", "%#{query}%", "%#{query}%"
      end

      if sort
        history = history.order(sort_reverse == "true" ? "#{sort} DESC" : sort)
      end

      if all
        [1, history]
      else
        page_count = (history.count.to_f / per_page).ceil
        [page_count, history.limit(per_page).offset((page.to_i - 1) * per_page)]
      end
    end

    # Fetch the history items for a specific object instance.
    def self.history_for_object(abstract_model, object, query, sort, sort_reverse)
      history = History.where :table => abstract_model.model.name, :item => object.id

      if query
        history = history.where "#{History.connection.quote_column_name(:message)} LIKE ? OR #{History.connection.quote_column_name(:username)} LIKE ?", "%#{query}%", "%#{query}%"
      end

      if sort
        history = history.order(sort_reverse == "true" ? "#{sort} DESC" : sort)
      end

      history
    end

    # Fetch the history item counts for a requested period of months
    def self.history_summaries(from, to, scope_adapter, authorization_adapter)
      month = from[:month].to_i
      histories = Array.new
      # cycle through each month and pull the history count, store the results for each month
      # in an array of hashes
      for  y in from[:year].to_i..to[:year].to_i 
        for  m in month..12 
          if m > to[:month].to_i && y == to[:year].to_i
            break
          end

          h = history_for_month(m, y, scope_adapter, authorization_adapter)
          histories << { :history => {:record_count => h.count , :year => y, :month => m }}

        end
        month = 1
      end

      histories
    end


    # Fetch the history item counts for the most recent 5 months.
    def self.history_latest_summaries(scope_adapter, authorization_adapter)
      from = {
        :month => 5.month.ago.month,
        :year => 5.month.ago.year,
      }
      to = {
        :month => DateTime.now.month,
        :year => DateTime.now.year,
      }
      self.history_summaries(from, to, scope_adapter, authorization_adapter)
    end
    
    
    # Fetch detailed history for one month.
    def self.history_for_month(month, year, scope_adapter, authorization_adapter, page = 1)
      filtered = Array.new      
      other_tables = Array.new

      history_rows = RailsAdmin::History.limit_scope(authorization_adapter, scope_adapter).where("month = ? and year = ?", month, year).paginate(:per_page => 60, :page => page).order("rails_admin_histories.created_at DESC")
    end

    # Fetch the most recent history item for a model.
    def self.most_recent_history(model)
      RailsAdmin::History.most_recent model
    end

  end

end