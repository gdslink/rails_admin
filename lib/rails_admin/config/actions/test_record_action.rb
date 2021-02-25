require 'openssl'
require 'base64'

module RailsAdmin
  module Config
    module Actions
      class TestRecordAction < RailsAdmin::Config::Actions::Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option :collection do
          true
        end

        register_instance_option :http_methods do
          [:get, :put]
        end

        register_instance_option :controller do
          proc do
            if request.get? # EDIT
              respond_to do |format|
                format.html { render @action.template_name }
                format.js   { render @action.template_name, layout: false }
              end

            elsif request.put? # UPDATE
              record = @application.get_mongoid_class.new
              testRecord = TestRecord.new
              testRecord.record_id = record["_id"].to_s
              testRecord.data_file_name = record["_id"].to_s
              testRecord.application_id = @application.id
              if params[:choice] == "Custom"
                inputs = params.select{|k, v| k =~ /_input/}
                inputsArray = inputs.to_a
                inputsArray.each{|inp|
                  recordName = inp[0].delete_suffix('_input')
                  recordName.sub! " ", "_"
                  record[recordName] = inp[1]
                }
              elsif params[:choice] == "Preset"
                inputs = params.select{|k, v| k =~ /Preset/}
                selectedFields = params[:fieldSelect]

                selectedFields.each{|sel|
                  if sel != ""
                    sel.sub! " ", "_"
                    origField = Field.where(:key => sel)
                    fieldType = origField[0].field_type
                    if fieldType == "String"
                      record[sel] = params[:stringPreset]
                    elsif fieldType == "Integer"
                      record[sel] = params[:integerPreset]
                    elsif fieldType == "Float"
                      record[sel] = params[:floatPreset]
                    elsif fieldType == "BigDecimal"
                      record[sel] = params[:decimalPreset]
                    elsif fieldType == "Money"
                      record[sel] = params[:moneyPreset]
                    elsif fieldType == "Date"
                      record[sel] = params[:datePreset]
                    end
                  end
                }
              elsif params[:choice] == "Random"
                selectedFields = params[:fieldSelect]
                selectedFields.each{|sel|
                  if sel != ""
                    sel.sub! " ", "_"
                    origField = Field.where(:key => sel)
                    fieldType = origField[0].field_type
                    if fieldType == "String"
                      record[sel] = (0..8).map { (65 + rand(26)).chr }.join
                    elsif fieldType == "Integer"
                      record[sel] = rand(0...1000)
                    elsif fieldType == "Float"
                      record[sel] = rand(0.00...1000.00)
                    elsif fieldType == "BigDecimal" || fieldType == "Money"
                      record[sel] = rand(0.00...1000.00).round(2)
                    elsif fieldType == "Date"
                      record[sel] = Time.at(0.0 + rand * (Time.now.to_f - 0.0.to_f))
                    end
                  end
                }
              end
              record.add_system_record(nil, @application, @company)
              if record.save
                testRecord.save
                respond_to do |format|
                  format.html { redirect_to_on_success }
                  format.js { render json: {id: testRecord.id.to_s, label: @model_config.with(object: testRecord).object_label} }
                end
              end
            end
          end
        end

        register_instance_option :link_icon do
          'icon-list-alt'
        end

        register_instance_option :pjax? do
          false
        end

        register_instance_option :visible? do
          is_visible = authorized?
          if !bindings[:controller].current_user.is_root && !bindings[:controller].current_user.is_admin && !bindings[:abstract_model].try(:model_name).nil?
            model_name = bindings[:controller].abstract_model.model_name
            is_visible = (bindings[:controller].current_ability.can? :"test_record_action_#{model_name}", bindings[:controller].current_scope["Company"][:selected_record]) && model_name == "TestRecord"
          end
          is_visible
        end

      end
    end
  end
end
