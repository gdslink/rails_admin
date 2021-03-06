RailsAdmin::Engine.routes.draw do

  # Prefix route urls with "admin" and route names with "rails_admin_"
  scope "history", :as => "history" do
    controller "history" do
      match "/list", :to => :list, :as => "list"
      match "/slider", :to => :slider, :as => "slider"
      match "/:model_name", :to => :for_model, :as => "model"
      match "/:model_name/:id", :to => :for_object, :as => "object"
    end
  end

  # Routes for rails_admin controller
  controller "main" do
    match "/", :to => :index, :as => "dashboard"
    match "/update_scope", :to => :update_scope, :as => "update_scope"
    match "/global_search", :to => :global_search, :as => "global_search"
    get "/:model_name", :to => :list, :as => "list"
    post "/:model_name/list", :to => :list, :as => "list_post"
    match "/:model_name/export", :to => :export, :as => "export"
    get "/:model_name/new", :to => :new, :as => "new"
    match "/:model_name/get_pages", :to => :get_pages, :as => "get_pages"
    post "/:model_name", :to => :create, :as => "create"
    match "/:model_name/system_import", :to => :system_import, :as => "system_import"
    match "/:model_name/system_export", :to => :system_export, :as => "system_export"
    match "/:model_name/field_import", :to => :field_import, :as => "field_import", via: [:get, :post]

    get "/:model_name/:id", :to => :show, :as => "show"
    get "/:model_name/:id/edit", :to => :edit, :as => "edit"    
    get "/:model_name/:id/show", :to => :show, :as => "show"
    put "/:model_name/:id", :to => :update, :as => "update"
    get "/:model_name/:id/delete", :to => :delete, :as => "delete"
    delete "/:model_name/:id", :to => :destroy, :as => "destroy"

    post "/:model_name/bulk_action", :to => :bulk_action, :as => "bulk_action"
    post "/:model_name/bulk_destroy", :to => :bulk_destroy, :as => "bulk_destroy"
  end
end
