require 'test_helper'

module Cms

  # This should be ported to features/content_pages.feature over time.
  class ContentControllerTest < ActionController::TestCase
    include Cms::ControllerTestHelper

    def setup
      given_there_is_a_guest_group
      given_there_is_a_cmsadmin
      given_there_is_a_sitemap
    end

    def test_show_another_page
      @page = create(:page, :section => root_section, :path => "/about", :name => "Test About", :template_file_name => "default.html.erb", :publish_on_save => true)
      get :show, :path => "about"
      assert_select "title", "Test About"
    end

    def test_page_not_found_to_cms_admin
      login_as_cms_admin
      get :show, :path => "foo"
      assert_response :not_found
      assert_select "title", "Page Not Found"
      assert_select "p", "There is no page at /foo"
    end

    def test_show_protected_page_to_privileged_user
      create_protected_page

      login_as @privileged_user

      get :show, :path => "secret"
      assert_response :success
      assert_select "title", "Shhh... It is a Secret"
    end

    def test_show_archived_page_to_user
      create_archived_page
      login_as_cms_admin

      get :show, :path => "archived"
      assert_response :success
      assert_select "title", "Archived"
    end

    def test_show_page_route
      @page_template = create(:page_template, :name => "test_show_page_route")
      @page = create(:page,
                      :section => root_section,
                      :template_file_name => "test_show_page_route.html.erb")
      @portlet = DynamicPortlet.create!(:name => "Test",
                                        :template => "<h1><%= @foo %></h1>",
                                        :connect_to_page_id => @page.id, :connect_to_container => "main")
      @page_route = @page.page_routes.create(:pattern => "/foo", :code => "@foo = params[:foo]")

      reset(:page)
      @page.publish!

      get :show_page_route, :foo => "42", :_page_route_id => @page_route.id
      assert_response :success
      assert_select "h1", "42"
    end

    def test_show_page_with_content
      create_page_with_content
      get :show, :path => "page_with_content"
      assert_response :success
      assert_select "h3", "TEST"
    end

    def test_is_file
      assert_is_file(true, "/system/file.pdf")
      assert_is_file(true, "/system/file.txt")
      assert_is_file(true, "/system/file.html")
      assert_is_file(false, "/system/file")
    end

    protected
    def assert_is_file(truth, path)
      @request = mock()
      @controller.expects(:request).returns(@request)
      @request.expects(:url).returns(path)
      assert_equal truth, @controller.send(:is_file?)
    end

    def create_protected_user_section_group
      @protected_section = create(:section, :parent => root_section)
      @secret_group = create(:group, :name => "Secret")
      @secret_group.sections << @protected_section
      @privileged_user = create(:user, :login => "privileged")
      @privileged_user.groups << @secret_group
    end

    def create_protected_page
      create_protected_user_section_group
      @page = create(:page,
                      :section => @protected_section,
                      :path => "/secret",
                      :name => "Shhh... It is a Secret",
                      :template_file_name => "default.html.erb",
                      :publish_on_save => true)
    end

    def create_file
      @file = mock_file(:content_type => "text/plain")
      @file_block = create(:file_block, :attachment_section => root_section, :attachment_file => @file, :attachment_file_path => "/test.txt", :publish_on_save => true)
    end

    def create_protected_file
      create_protected_user_section_group
      create_file
      reset(:file_block)
      @file_block.update_attributes(:attachment_section => @protected_section)
      reset(:file_block)
    end

    def create_archived_page
      @page = create(:page,
                      :section => root_section,
                      :path => "/archived",
                      :name => "Archived",
                      :archived => true,
                      :template_file_name => "default.html.erb",
                      :publish_on_save => true)
    end

    def create_page_with_content
      @page_template = create(:page_template, :name => "testing_editting_content")

      @page = create(:page,
                      :section => root_section,
                      :path => "/page_with_content",
                      :template_file_name => "testing_editting_content.html.erb")

      @block = HtmlBlock.create!(:name => "Test",
                                 :content => "<h3>TEST</h3>",
                                 :connect_to_page_id => @page.id,
                                 :connect_to_container => "main")

      reset(:page)
      @page.publish!

    end

  end

# CMS Page Caching Enabled (Production Mode)
#   Logged in as guest
#         mysite.com/page         -> serves cached page
#     cms.mysite.com/page         -> redirect to mysite.com/page
#
#   Logged in as a registered user
#         mysite.com/page         -> serves cached page
#     cms.mysite.com/page         -> redirect to mysite.com/page
#
#   Logged in as cms user
#         mysite.com/page         -> serves cached page
#     cms.mysite.com/page         -> renders cms page editor
  class ContentCachingEnabledControllerTest < ActionController::TestCase
    tests Cms::ContentController
    include Cms::ControllerTestHelper

    def setup
      given_there_is_a_guest_group
      given_there_is_a_cmsadmin
      given_there_is_a_sitemap
      ActionController::Base.perform_caching = true
      @page = create(:page, :section => root_section, :name => "Test Page", :path => "/page", :publish_on_save => true)
      @registered_user = create(:user)
      @registered_user.groups << Group.guest
    end

    def teardown
      ActionController::Base.perform_caching = false
    end

    def test_guest_user_views_page_on_public_site
      @request.host = "mysite.com"
      get :show, :path => "page"
      assert_response :success
      assert_select "title", "Test Page"
    end


    def test_registered_user_views_page_on_public_site
      login_as @registered_user
      @request.host = "mysite.com"

      get :show, :path => "page"

      assert_response :success
      assert_select "title", "Test Page"
    end

    def test_cms_user_views_page_on_public_site
      login_as_cms_admin
      @request.session[:page_mode] = "edit"
      @request.host = "mysite.com"

      get :show, :path => "page"

      assert_response :success
      assert_select "title", "Test Page"
      assert_select "iframe", {:count => 0}
    end

    def test_cms_user_views_page_on_cms_site_with_caching
      login_as_cms_admin
      @request.session[:page_mode] = "edit"
      @request.host = "cms.mysite.com"

      get :show, :path => "page", :use_route => false

      assert_response :success
      assert_select "title", "Test Page"
    end

  end

# CMS Page Caching Disabled (Development Mode)
#   Logged in as guest
#         mysite.com/page         -> renders page
#     cms.mysite.com/page         -> renders page
#
#   Logged in as a registered user
#         mysite.com/page         -> renders page
#     cms.mysite.com/page         -> renders page
#
#   Logged in as cms user
#         mysite.com/page         -> renders cms page editor
#     cms.mysite.com/page         -> renders cms page editor
  class ContentCachingDisabledControllerTest < ActionController::TestCase
    tests Cms::ContentController
    include Cms::ControllerTestHelper

    def setup
      given_there_is_a_guest_group
      given_there_is_a_cmsadmin
      given_there_is_a_sitemap
      ActionController::Base.perform_caching = false
      @page = create(:page, :section => root_section, :name => "Test Page", :path => "/page", :publish_on_save => true)
      @registered_user = create(:user)
      @registered_user.groups << Group.guest
    end

    def test_guest_user_views_page_on_public_site
      @request.host = "mysite.com"
      get :show, :path => "page"
      assert_response :success
      assert_select "title", "Test Page"
    end

    def test_guest_user_views_page_on_cms_site
      @request.host = "mysite.com"
      get :show, :path => "page"
      assert_response :success
      assert_select "title", "Test Page"
    end

    def test_registered_user_views_page_on_public_site
      login_as @registered_user
      @request.host = "mysite.com"

      get :show, :path => "page"

      assert_response :success
      assert_select "title", "Test Page"
    end

    def test_registered_user_views_page_on_cms_site
      login_as @registered_user
      @request.host = "mysite.com"

      get :show, :path => "page"

      assert_response :success
      assert_select "title", "Test Page"
    end

    def test_cms_user_views_page_on_public_site
      login_as_cms_admin
      @request.session[:page_mode] = "edit"
      @request.host = "mysite.com"

      get :show, :path => "page"

      assert_response :success
      assert_select "title", "Test Page"
    end

    def test_cms_user_views_page_on_cms_site
      login_as_cms_admin
      @request.session[:page_mode] = "edit"
      @request.host = "cms.mysite.com"

      get :show, :path => "page", :use_route => false

      assert_response :success
      assert_select "title", "Test Page"
    end
  end
end
