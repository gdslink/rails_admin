class AddCompanyLogo < ActiveRecord::Migration
  def self.up
    add_column :companies, :logo_image_uid,  :string
  end
 
  def self.down
    remove_column :companies, :logo_image_uid
  end
end
