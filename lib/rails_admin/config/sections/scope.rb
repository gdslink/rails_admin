require 'rails_admin/config/base'
require 'rails_admin/config/hideable'

module RailsAdmin
  module Config
    # Configuration of the scope to be used in the DB queries for the current view    
    class Scope < RailsAdmin::Config::Base
      # Defines the columns and fields that should be used to scope the db queries
      register_class_option(:models) do
        []
      end
    end
  end
end