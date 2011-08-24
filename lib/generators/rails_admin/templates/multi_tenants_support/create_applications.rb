class CreateApplications < ActiveRecord::Migration
  def self.up
    create_table :applications do |t|
      t.string :name, :null => false
      t.string :key, :null => false
      t.string :description
      t.references :company, :null => false
      t.timestamps
    end
  end

  def self.down
    drop_table :applications
  end
end
