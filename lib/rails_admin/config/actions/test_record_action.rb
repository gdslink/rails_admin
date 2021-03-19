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
              #Only create records
              if params[:genRecordInput] == "Yes"
                if !params[:previousSelectedFields].nil?
                  selectedFields = params[:fieldSelect].concat JSON.parse(params[:previousSelectedFields])
                else
                  selectedFields = params[:fieldSelect]
                end
                numberOfRecords = params[:numOfRecordsInput].to_i
                tableParams = params.select{|k| k.starts_with? "table_"}
                fieldParams = params.select{|k| k.starts_with? "field_"}
                fieldParamInputs = fieldParams.select{|field| field.end_with? "_input"}
                tableParamInputs = tableParams.select{|table| table.end_with? "_input"}
                loopNumber = 1
                selectedTables = []
                while loopNumber <= numberOfRecords do  
                  record = @application.get_mongoid_class.new
                  #Loop over tables
                  tableParamInputs.each{|selFieldIn|
                    selField = selFieldIn[0]
                    #Check if the selected field is a table, if so push to selectedTables array.
                    if !tableParams.nil?
                      selectedFields.each{|x|
                        if x != ""
                          if selField.start_with? "table_" + x
                            selectedTables.push(x)
                          end
                        end
                      }
                    end
                  }
                  #Now have the fields that were selected that are tables in selectedTables array.
                  selectedTables = selectedTables.uniq
                  #Sort array by length, longest first so the tableParamInputs.select works correctly (e.g. child_table and child_table_2)
                  selectedTables = selectedTables.sort_by(&:length)
                  selectedTables = selectedTables.reverse
                  selectedTables.each{|table|
                    #Setup access to the table in the record.
                    underscoredName = table.gsub(" ", "_")
                    appTableName = table.titlecase.gsub(" ", "")
                    compAppTable = @company.name + @application.name + appTableName
                    tableArray = []
                    #Find and loop over relevant inputs for this table.
                    currentTableInputs = tableParamInputs.select{|tableField| tableField.start_with? "table_" + table + "_field_"}
                    tableIteration1 = params[table+"iteration_input"].to_i
                    tableIteration2 = params[table+"second_iteration_input"].to_i
                    if tableIteration2 < 2
                      numberOfIterations = 1
                    else
                      numberOfIterations = rand(tableIteration1...tableIteration2)
                    end
                    tableIteration1 -= 1
                    numberOfIterations -= 1
                    while tableIteration1 <= numberOfIterations do
                      tableArray[tableIteration1] = compAppTable.constantize.new
                      currentTableInputs.each{|tabInput|
                        tabField = tabInput[0]
                        fieldDropdownName = tabField.delete_suffix('_input')
                        tabDropDown = params[fieldDropdownName + "_dropdown"]
                        if tabDropDown == "Defined value"
                          input = params[tabField]
                          origFieldValue = tabField.delete_prefix("table_" + table + "_field_").delete_suffix("_input")
                          recordField = origFieldValue.gsub(" ", "_")
                          tableArray[tableIteration1][recordField] = input
                        elsif tabDropDown == "Value from list"
                          input = params[tabField]
                          origFieldValue = tabField.delete_prefix("table_" + table + "_field_").delete_suffix("_input")
                          recordField = origFieldValue.gsub(" ", "_")
                          seperator = params["table_" + table + "_field_" + origFieldValue + "_seperator"]
                          input = input.split(seperator)
                          tableArray[tableIteration1][recordField] = input.sample
                        elsif tabDropDown == "Random value"
                          origFieldValue = tabField.delete_prefix("table_" + table + "_field_").delete_suffix("_input")
                          recordField = origFieldValue.gsub(" ", "_")
                          origField = Field.where(:key => recordField)
                          fieldType = origField[0].field_type
                          if fieldType == "String"
                            tableArray[tableIteration1][recordField] = (0..8).map { (65 + rand(26)).chr }.join
                          elsif fieldType == "Integer"
                            tableArray[tableIteration1][recordField] = rand(0...1000)
                          elsif fieldType == "Float"
                            tableArray[tableIteration1][recordField] = rand(0.00...1000.00)
                          elsif fieldType == "BigDecimal" || fieldType == "Money"
                            tableArray[tableIteration1][recordField] = rand(0.00...1000.00).round(2)
                          elsif fieldType == "Date"
                            tableArray[tableIteration1][recordField] = Time.at(0.0 + rand * (Time.now.to_f - 0.0.to_f))
                          end
                        end
                      }
                      tableIteration1 += 1
                    end
                    record.public_send(underscoredName+"=", tableArray)
                  }
                  #Continue for individual fields
                  fieldParamInputs.each{|selFieldIn|
                    selField = selFieldIn[0]
                    if selField != ""
                      fieldDropdownName = selField.delete_suffix('_input')
                      selDropDown = params[fieldDropdownName + "_dropdown"]
                      if selDropDown == "Defined value"
                        input = params[selField]
                        origFieldValue = selField.delete_prefix("field_").delete_suffix("_input")
                        recordField = origFieldValue.gsub(" ", "_")
                        record[recordField] = input
                      elsif selDropDown == "Value from list"
                        input = params[selField]
                        origFieldValue = selField.delete_prefix("field_").delete_suffix("_input")
                        recordField = origFieldValue.gsub(" ", "_")
                        seperator = params["field_" + origFieldValue + "_seperator"]
                        input = input.split(seperator)
                        record[recordField] = input.sample
                      elsif selDropDown == "Random value"
                        origFieldValue = selField.delete_prefix("field_").delete_suffix("_input")
                        origFieldValue.gsub(" ", "_")
                        origField = Field.where(:key => origFieldValue)
                        fieldType = origField[0].field_type
                        if fieldType == "String"
                          record[origFieldValue] = (0..8).map { (65 + rand(26)).chr }.join
                        elsif fieldType == "Integer"
                          record[origFieldValue] = rand(0...1000)
                        elsif fieldType == "Float"
                          record[origFieldValue] = rand(0.00...1000.00)
                        elsif fieldType == "BigDecimal" || fieldType == "Money"
                          record[origFieldValue] = rand(0.00...1000.00).round(2)
                        elsif fieldType == "Date"
                          record[origFieldValue] = Time.at(0.0 + rand * (Time.now.to_f - 0.0.to_f))
                        end
                      end
                    end
                  }
                  record.add_system_record(nil, @application, @company)
                  record.save
                  loopNumber += 1
                end
              #Only create testRecord
              else
                testRecord = TestRecord.new
                testRecord.template_name = params[:templateName]
                testRecord.application_id = @application.id
                selectedFields = params[:fieldSelect]
                testRecord.selected_fields = selectedFields
                testRecord.selected_inputs = params.select{|k| k.end_with? "_input"}.to_json
                testRecord.selected_dropdowns = params.select{|k| k.end_with? "_dropdown"}.to_json
                testRecord.selected_seperators = params.select{|k| k.end_with? +"_seperator"}.to_json
                numberOfRecords = params[:numOfRecordsInput].to_i
                testRecord.number_of_records = numberOfRecords
                tableParams = params.select{|k| k.starts_with? "table_"}
                tableParamInputs = tableParams.select{|table| table.end_with? "_input"}
                selectedTables = []
                record = @application.get_mongoid_class.new
                testRecord.data_file_name = record["_id"].to_s
                #Loop over tables
                tableParamInputs.each{|selFieldIn|
                  selField = selFieldIn[0]
                  #Check if the selected field is a table, if so push to selectedTables array.
                  if !tableParams.nil?
                    selectedFields.each{|x|
                      if x != ""
                        if selField.start_with? "table_" + x
                          selectedTables.push(x)
                        end
                      end
                    }
                  end
                }
                #Now have the fields that were selected that are tables in selectedTables array.
                selectedTables = selectedTables.uniq
                #Sort array by length, longest first so the tableParamInputs.select works correctly (e.g. child_table and child_table_2)
                selectedTables = selectedTables.sort_by(&:length)
                selectedTables = selectedTables.reverse
                testRecord.selected_tables = selectedTables.to_json
                if testRecord.save
                  respond_to do |format|
                    format.html { redirect_to_on_success }
                    format.js { render json: {id: testRecord.id.to_s, label: @model_config.with(object: testRecord).object_label} }
                  end
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
