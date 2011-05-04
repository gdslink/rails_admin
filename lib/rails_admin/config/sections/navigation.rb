require 'rails_admin/config/base'
require 'rails_admin/config/hideable'

module RailsAdmin
  module Config
    module Sections
      # Configuration of the navigation view
      class Navigation < RailsAdmin::Config::Base        
        register_class_option(:accordion_navigation) do
          {
            :sections => [
            {
                 :label => I18n.t("admin.dashboard.name"),
                 :image => "rails_admin/icons/house.png",
                 :links => [
                     {
                         :url_for => {:action => :dashboard, :model => nil},
                         :label => I18n.t("admin.dashboard.name"),
                         :image => "rails_admin/icons/application_home.png" 
                     }
                 ] 
             }]
          }
        end
      end
    end
  end
end
