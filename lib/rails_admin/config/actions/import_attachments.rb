module RailsAdmin
  module Config
    module Actions
      class ImportAttachments < RailsAdmin::Config::Actions::Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option :collection do
          true
        end

        register_instance_option :http_methods do
          [:get, :put]
        end

        register_instance_option :controller do
          proc do
            if request.get? # UPDATE
            end
          end
        end

        register_instance_option :link_icon do
          'icon-list-alt'
        end
      end
    end
  end
end