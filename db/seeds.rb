#create initial user
u = User.find_or_create_by_email(:email => 'root@domain.com', :password => 'root1234')

#create initial role
r = AdminRole.find_or_create_by_name(:name => 'root', :description => "Root gives access to everything")

#associate user role

u.roles << r

#create root permission
p = AdminPermission.find_or_create_by_name(:name => "No restrictions", :action => :manage, :subject_class => :all)

r.admin_permissions << p