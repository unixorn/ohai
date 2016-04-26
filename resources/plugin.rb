property :plugin_name, kind_of: String, name_attribute: true
property :path, kind_of: String
property :source_file, kind_of: String
property :compile_time, [true, false], default: true

action_class do
  # return the path property if specified or
  # CHEF_CONFIG_PATH/ohai/plugins if a path isn't specified
  def desired_plugin_path
    if path
      path
    else
      ohai_plugin_path
    end
  end

  # return the chef config files dir or fail hard
  def chef_config_path
    if Chef::Config['config_file']
      ::File.dirname(Chef::Config['config_file'])
    else
      Chef::Application.fatal!("No chef config file defined. Are you running \
                                chef-solo? If so you will need to define a path \
                                for the ohai_plugin as the path cannot be determined")
    end
  end

  # return the ohai plugin path. Most likely /etc/chef/ohai/plugins/
  def ohai_plugin_path
    ::File.join(chef_config_path, 'ohai', 'plugins')
  end

  # is the desired plugin dir in the ohai config plugin dir array?
  def in_plugin_path?(path)
    # get the directory where we plan to stick the plugin (not the actual file path)
    desired_dir = ::File.dirname(path)

    # get the array of plugin paths Ohai knows about
    ohai_plugin_dir = if node['chef_packages']['ohai']['version'].to_f <= 8.6
                        ::Ohai::Config['plugin_path']
                      else
                        ::Ohai::Config.ohai['plugin_path']
                      end

    ohai_plugin_dir.include?(desired_dir)
  end

  # we need to warn the user that unless the path for this plugin is in Ohai's
  # plugin path already we're going to have to reload Ohai on every Chef run.
  # Ideally in future versions of Ohai /etc/chef/ohai/plugins is in the path.
  def plugin_path_warning
    Chef::Log.warn("The Ohai plugin_path does not include #{desired_plugin_path}. \
                    Ohai will reload on each chef-client run in order to add \
                    this directory to the path unless you modify your client.rb \
                    configuration to add this directory to plugin_path. See \
                    https://docs.chef.io/config_rb_client.html")
  end
end

action :create do
  reload_required = !in_plugin_path?(desired_plugin_path)

  # throw a warning unless the path of our new plugin is in Ohai's plugin path
  plugin_path_warning if reload_required

  # why create_if_missing you ask?
  # no one can agree on perms and this allows them to manage the perms elsewhere
  directory desired_plugin_path do
    action :create
    recursive true
    not_if { ::File.exist?(desired_plugin_path) }
  end

  cookbook_file ::File.join(desired_plugin_path, new_resource.plugin_name) do
    source new_resource.source_file || "#{new_resource.plugin_name}.rb"
    owner 'root'
    group 'root'
    mode 00644
    notifies :reload, "ohai[#{new_resource.plugin_name}]", :immediately
  end

  ohai new_resource.plugin_name do
    action :nothing
  end
end

# this resource forces itself to run at compile_time
def after_created
  if compile_time
    Array(action).each do |action|
      run_action(action)
    end
  end
end
