#create initial user
u = User.find_or_create_by_email(:email => 'root@domain.com', :password => 'root1234', :is_root => true)