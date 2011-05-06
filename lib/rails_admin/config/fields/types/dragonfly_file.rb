require 'rails_admin/config/fields/base'
require 'rails_admin/config/fields/types/file_upload'

module RailsAdmin
  module Config
    module Fields
      module Types
        # Field type that supports Dragonfly file uploads
        class DragonflyFile < RailsAdmin::Config::Fields::Types::FileUpload
          RailsAdmin::Config::Fields::Types.register(self)

          register_instance_option(:partial) do
            :dragonfly_file
          end

          def value
            # if bindings[:object].send(name).file?
            #   bindings[:object].send(name).url
            # else
            #   nil
            # end
          end
        end
      end
    end
  end
end
