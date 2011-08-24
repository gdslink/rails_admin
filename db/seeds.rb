#create initial user
u = User.find_or_create_by_email(:email => 'root@domain.com', :password => 'root1234')

#create initial role
r = Role.find_or_create_by_name(:name => 'root', :description => "Root gives access to everything")

#associate user role

u.roles << r

#create root permission
p = Permission.find_or_create_by_name(:name => "No restrictions", :action => :manage, :subject_class => :all)

r.permissions << p