class CreatePermissions < ActiveRecord::Migration
  def self.up    
    create_table :permissions do |t|
      t.string :name, :null => false
      t.string :action
      t.string :subject_class
      t.boolean :visible, :default => false
      t.timestamps
    end
  end

  def self.down
    drop_table :users_permissions
    drop_table :permissions    
  end
end
