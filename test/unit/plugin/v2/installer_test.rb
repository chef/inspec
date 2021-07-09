require "helper"

require "fileutils"
require "json"
require "inspec/plugin/v2"
require "inspec/plugin/v2/installer"

Gem.done_installing_hooks.clear # Remove rdoc generation

module InstallerTestHelpers
  RUN_SLOW = ENV["SLOW"]
  RUN_LIVE_NET = ENV["LIVE_NET"]

  def skip_slow_tests
    skip "slow" unless RUN_SLOW
  end

  def skip_live_net_tests
    skip "This test talks on the network" unless RUN_LIVE_NET
  end

  def reset_globals
    ENV["HOME"] = @@orig_home
    ENV["INSPEC_CONFIG_DIR"] = nil
    @installer && @installer.__reset
    if defined?(::InspecPlugins::TestFixture)
      InspecPlugins.send :remove_const, :TestFixture
    end
    # forget all test fixture files
    $".reject! { |path| path =~ %r{test/fixtures} }
  end

  def copy_in_config_dir(fixture_name)
    src = Dir.glob(File.join(@config_dir_path, fixture_name, "*"))
    dest = File.join(@config_dir_path, "empty")
    src.each { |path| FileUtils.cp_r(path, dest) }
  end

  @@orig_home = Dir.home

  def setup
    WebMock.disable_net_connect!(allow: %r{((api|index)\.)?rubygems\.org/.*}) if RUN_LIVE_NET

    repo_path = File.expand_path(File.join( __FILE__, "..", "..", "..", "..", ".."))
    mock_path = File.join(repo_path, "test", "fixtures")

    @config_dir_path = File.join(mock_path, "config_dirs")
    @plugin_fixture_src_path = File.join(mock_path, "plugins", "inspec-test-fixture")
    @plugin_fixture_pkg_path = File.join(@plugin_fixture_src_path, "pkg")

    # This is unstable under CI; see https://github.com/inspec/inspec/issues/3355
    @ruby_abi_version = RbConfig::CONFIG["ruby_version"]

    @installer = Inspec::Plugin::V2::Installer.instance

    ENV["INSPEC_CONFIG_DIR"] = File.join(@config_dir_path, "empty")
    ENV["HOME"] = File.join(@config_dir_path, "fakehome")
    Gem.paths = ENV
    @installer.__reset_loader
    @installer.__reset
  end

  def teardown
    reset_globals

    # We use the 'empty' config dir for exercising a lot of installs.
    # Purge it after every test.
    unless ENV["INSPEC_TEST_PRESERVE_PLUGIN"]
      if @config_dir_path
        Dir.glob(File.join(@config_dir_path, "empty", "*")).each do |path|
          next if path.end_with? ".gitkeep"

          FileUtils.rm_rf(path)
        end
      end
    end

    # Clean up any activated gems
    Gem.loaded_specs.delete("inspec-test-fixture")
    Gem.loaded_specs.delete("ordinal_array")
  end
end

#-----------------------------------------------------------------------#
# basics
#-----------------------------------------------------------------------#
class PluginInstallerBasicTests < Minitest::Test
  include InstallerTestHelpers

  # it's a singleton
  def test_it_should_be_a_singleton
    klass = Inspec::Plugin::V2::Installer
    assert_equal klass.instance, klass.instance, "Calling instance on the Installer should always return the same object"
    assert_kind_of Inspec::Plugin::V2::Installer, klass.instance, "Calling instance on the INstaller should return the right class"
    assert_raises(NoMethodError, "Installer should have a private constructor") { klass.new }
  end

  # it should know its gem path
  def test_it_should_know_its_gem_path_with_a_default_location
    ENV.delete "INSPEC_CONFIG_DIR"
    ENV["HOME"] = File.join(@config_dir_path, "fakehome")

    suffix = "fakehome/.inspec/gems/#{@ruby_abi_version}"
    assert_operator @installer.gem_path, :end_with?, suffix
  end

  def test_it_should_know_its_gem_path_with_a_custom_config_dir_from_env
    suffix = "empty/gems/#{@ruby_abi_version}"
    assert_operator @installer.gem_path, :end_with?, suffix
  end
end

#-----------------------------------------------------------------------#
# Installing
#-----------------------------------------------------------------------#
class PluginInstallerInstallationTests < Minitest::Test
  include InstallerTestHelpers

  # While this is a negative test case on the prefix checking, there are
  # several positive test cases following.
  def test_refuse_to_install_gems_with_wrong_name_prefix
    # Here, ordinal_array is the name of a simple, small gem available on rubygems.org
    # There is no significance in choosing that gem over any other.
    # Main point here is that its name does not begin with 'inspec-'.
    assert_raises(Inspec::Plugin::V2::InstallError) { @installer.install("ordinal_array") }
  end

  def test_install_a_gem_from_local_file
    skip_live_net_tests # This still accesses rubygems.org to check for deps

    gem_file = File.join(@plugin_fixture_pkg_path, "inspec-test-fixture-0.1.0.gem")

    assert_operator File, :exist?, gem_file

    reg = Inspec::Plugin::V2::Registry.instance
    plugin_name = :'inspec-test-fixture'
    refute_operator reg, :known_plugin?,  plugin_name
    refute_operator reg, :loaded_plugin?, plugin_name

    @installer.install("inspec-test-fixture", gem_file: gem_file)

    base = @installer.gem_path
    spec_path = "#{base}/specifications/inspec-test-fixture-0.1.0.gemspec"
    installed_gem_base = "#{base}/gems/inspec-test-fixture-0.1.0"

    assert_operator File, :exist?, spec_path
    assert_operator Dir, :exist?, installed_gem_base

    # Installation = gem activation
    spec = Gem.loaded_specs["inspec-test-fixture"]

    assert_operator spec, :activated?
  end

  def test_install_a_gem_from_missing_local_file
    gem_file = File.join(@plugin_fixture_pkg_path, "inspec-test-fixture-nonesuch-0.0.0.gem")

    refute File.exist?(gem_file), "The nonexistant gem should not exist prior to install attempt"
    ex = assert_raises(Inspec::Plugin::V2::InstallError) { @installer.install("inspec-test-fixture-nonesuch", gem_file: gem_file) }
    assert_includes ex.message, "Could not find local gem file"
  end

  def test_install_a_gem_from_local_file_creates_plugin_json
    skip_live_net_tests # This still accesses rubygems.org to check for deps

    gem_file = File.join(@plugin_fixture_pkg_path, "inspec-test-fixture-0.1.0.gem")
    stdout, _stderr = capture_io do
      @installer.install("inspec-test-fixture", gem_file: gem_file)
    end

    # Should now be present in plugin.json
    plugin_json_path = File.join(ENV["INSPEC_CONFIG_DIR"], "plugins.json")
    assert File.exist?(plugin_json_path), "plugins.json should now exist"
    config_file = Inspec::Plugin::V2::ConfigFile.new(plugin_json_path)

    assert_equal 1, config_file.count, "plugins.json should have one entry"
    assert config_file.existing_entry?(:'inspec-test-fixture')

    # Should not try to install docs
    # Installing ri documentation for ...
    # Parsing documentation for ...
    refute_match(/Installing ri documentation for/, stdout)
    refute_match(/Installing rdoc documentation for/, stdout)
  end

  def test_install_a_gem_from_rubygems_org
    skip_slow_tests
    skip_live_net_tests

    capture_subprocess_io do
      @installer.install("inspec-test-fixture")
    end

    # Because no exception was thrown, this is a positive test case for prefix-checking.

    # Installing a gem places it under the config dir gem area
    spec_path = File.join(@installer.gem_path, "specifications", "inspec-test-fixture-0.2.0.gemspec")
    assert File.exist?(spec_path), "After installation from rubygems.org, the gemspec should be installed to the gem path"
    installed_gem_base = File.join(@installer.gem_path, "gems", "inspec-test-fixture-0.2.0")
    assert Dir.exist?(installed_gem_base), "After installation from rubygems.org, the gem tree should be installed to the gem path"

    # installing a gem with dependencies should result in the deps being installed under the config dir
    spec_path = File.join(@installer.gem_path, "specifications", "ordinal_array-0.2.0.gemspec")
    assert File.exist?(spec_path), "After installation from a gem file, the gemspec should be installed to the gem path"
    installed_gem_base = File.join(@installer.gem_path, "gems", "inspec-test-fixture-0.2.0")
    assert Dir.exist?(installed_gem_base), "After installation from a gem file, the gem tree should be installed to the gem path"

    # Installation != gem activation
    spec = Gem.loaded_specs["inspec-test-fixture"]
    assert spec.activated?, "Installing a gem should cause the gem to activate"
  end

  def test_handle_no_such_gem
    skip_slow_tests
    skip_live_net_tests

    assert_raises(Inspec::Plugin::V2::InstallError) { @installer.install("inspec-test-fixture-nonesuch") }
  end

  # Should be able to install a plugin while pinning the version
  def test_install_a_pinned_gem_from_rubygems_org
    skip_slow_tests
    skip_live_net_tests

    capture_subprocess_io do
      @installer.install("inspec-test-fixture", version: "= 0.1.0")
    end

    # Installing a gem places it under the config dir gem area
    spec_path = File.join(@installer.gem_path, "specifications", "inspec-test-fixture-0.1.0.gemspec")
    assert File.exist?(spec_path), "After pinned installation from rubygems.org, the gemspec should be installed to the gem path"
    spec_path = File.join(@installer.gem_path, "specifications", "inspec-test-fixture-0.2.0.gemspec")
    refute File.exist?(spec_path), "After pinned installation from rubygems.org, the wrong gemspec version should be absent"

    config_file = Inspec::Plugin::V2::ConfigFile.new
    entry = config_file.plugin_by_name(:'inspec-test-fixture')
    assert_includes entry.keys, :version, "plugins.json should include version pinning key"
    assert_equal "= 0.1.0", entry[:version], "plugins.json should include version pinning value"
  end

  def test_install_a_gem_with_conflicting_depends_from_rubygems_org
    skip_live_net_tests

    spec = Gem::Specification._all.find { |s| s.name == "rake" }
    spec.activate

    ex = assert_raises(Inspec::Plugin::V2::InstallError) do
      @installer.install("inspec-test-fixture", version: "= 0.1.1")
    end
    assert_includes ex.message, "can't activate rake-0.4.8, already activated rake-"
  end

  def test_install_a_gem_with_invalid_depends_from_rubygems_org
    skip_slow_tests
    skip_live_net_tests

    ex = assert_raises(Inspec::Plugin::V2::InstallError) do
      @installer.install("inspec-test-fixture", version: "= 0.1.2")
    end
    assert_includes ex.message, "Could not find 'fake_plugin_dependency' (>= 0)"
  end

  def test_install_a_plugin_from_a_path
    @installer.install("inspec-test-fixture", path: @plugin_fixture_src_path)

    # No gemspec should exist in the plugins area
    specs = Dir.glob(File.join(@installer.gem_path, "specifications", "*.gemspec"))
    assert_empty specs, "After install-from-path, no gemspecs should be installed"

    config_file = Inspec::Plugin::V2::ConfigFile.new
    entry = config_file.plugin_by_name(:'inspec-test-fixture')
    assert_includes entry.keys, :installation_type, "plugins.json should include installation_type key"
    assert_equal :path, entry[:installation_type], "plugins.json should include path installation_type"

    assert_includes entry.keys, :installation_path, "plugins.json should include installation_path key"
    assert_equal @plugin_fixture_src_path, entry[:installation_path], "plugins.json should include correct value for installation path"
  end

  def test_refuse_to_install_gem_whose_name_is_on_the_reject_list
    # Here, 'inspec-core', 'inspec-multi-server', and 'train-tax-collector'
    # are the names of real rubygems.  They are not InSpec/Train plugins, though,
    # and installing them would be a jam-up.
    # This is configured in 'etc/plugin-filter.json'.
    %w{
      inspec-core
      inspec-multi-server
      train-tax-calculator
    }.each do |plugin_name|
      ex = assert_raises(Inspec::Plugin::V2::InstallError) { @installer.install(plugin_name) }
      assert_includes(ex.message, "on the Plugin Exclusion List")
      assert_includes(ex.message, "Rationale:")
    end
  end
end

#-----------------------------------------------------------------------#
# Updating
#-----------------------------------------------------------------------#
class PluginInstallerUpdaterTests < Minitest::Test
  include InstallerTestHelpers

  def test_update_using_path_not_allowed
    assert_raises(Inspec::Plugin::V2::UpdateError) do
      @installer.update("inspec-test-fixture", path: @plugin_fixture_src_path)
    end
  end

  def test_update_existing_plugin_at_same_version_not_allowed
    copy_in_config_dir("test-fixture-1-float")

    assert_raises(Inspec::Plugin::V2::UpdateError) do
      @installer.update("inspec-test-fixture", version: "0.1.0")
    end
  end

  def test_install_plugin_at_existing_version_not_allowed
    copy_in_config_dir("test-fixture-1-float")

    assert_raises(Inspec::Plugin::V2::InstallError) do
      @installer.install("inspec-test-fixture", version: "0.1.0")
    end
  end

  def test_install_existing_plugin_not_allowed
    copy_in_config_dir("test-fixture-1-float")

    ex = assert_raises(Inspec::Plugin::V2::InstallError) do
      @installer.install("inspec-test-fixture")
    end
    assert_includes ex.message, "Use 'inspec plugin update'"
  end

  def test_update_to_latest_version
    skip_slow_tests
    skip_live_net_tests

    copy_in_config_dir("test-fixture-1-float")
    @installer.__reset_loader

    capture_subprocess_io do
      @installer.update("inspec-test-fixture")
    end

    # Verify presence of gemspecs
    spec_path = File.join(@installer.gem_path, "specifications", "inspec-test-fixture-0.2.0.gemspec")
    assert File.exist?(spec_path), "After update, the 0.2.0 gemspec should be installed to the gem path"
    spec_path = File.join(@installer.gem_path, "specifications", "inspec-test-fixture-0.1.0.gemspec")
    assert File.exist?(spec_path), "After update, the 0.1.0 gemspec should remain"

    # Plugins file entry should now be version pinned to latest
    plugin_json_path = File.join(ENV["INSPEC_CONFIG_DIR"], "plugins.json")
    plugin_json_data = JSON.parse(File.read(plugin_json_path))
    entry = plugin_json_data["plugins"].detect { |e| e["name"] == "inspec-test-fixture" }
    assert_equal "= 0.2.0", entry["version"]
  end

  def test_update_to_specified_later_version
    skip_slow_tests
    skip_live_net_tests

    copy_in_config_dir("test-fixture-1-float")
    @installer.__reset_loader

    # Update to specific (but later) version

    capture_subprocess_io do
      @installer.update("inspec-test-fixture", version: "0.2.0")
    end

    # Verify presence of gemspecs
    spec_path = File.join(@installer.gem_path, "specifications", "inspec-test-fixture-0.2.0.gemspec")
    assert File.exist?(spec_path), "After update, the 0.2.0 gemspec should be installed to the gem path"
    spec_path = File.join(@installer.gem_path, "specifications", "inspec-test-fixture-0.1.0.gemspec")
    assert File.exist?(spec_path), "After update, the 0.1.0 gemspec should remain"

    # Plugins file entry should be version pinned
    config_file = Inspec::Plugin::V2::ConfigFile.new
    entry = config_file.plugin_by_name(:'inspec-test-fixture')
    assert_includes entry.keys, :version, "plugins.json should include version pinning key"
    assert_equal "= 0.2.0", entry[:version], "plugins.json should include version pinning value"
  end

  # TODO: Prevent updating a gem if it will lead to unsolveable dependencies
  # TODO: allow updating a gem that will lead to unsolveable dependencies if :force is provided
  # TODO: Prevent downgrading a gem if it will lead to unsolveable dependencies
  # TODO: allow downgrading a gem that will lead to unsolveable dependencies if :force is provided
  # TODO: update all
  # TODO: downgrade a plugin
  # TODO: Trying to do a gemfile install with an update is an error if the file version matches the installed version

end

#-----------------------------------------------------------------------#
# Uninstalling
#-----------------------------------------------------------------------#
class PluginInstallerUninstallTests < Minitest::Test
  include InstallerTestHelpers

  def test_uninstalling_a_nonexistant_plugin_is_an_error
    # Try a mythical one
    ex = assert_raises(Inspec::Plugin::V2::UnInstallError) do
      @installer.uninstall("inspec-test-fixture-nonesuch")
    end
    assert_includes ex.message, "'inspec-test-fixture-nonesuch' is not installed, refusing to uninstall."

    # Try a real plugin that is not installed
    ex = assert_raises(Inspec::Plugin::V2::UnInstallError) do
      @installer.uninstall("inspec-test-fixture")
    end
    assert_includes ex.message, "'inspec-test-fixture' is not installed, refusing to uninstall."
  end

  def test_uninstalling_a_path_based_plugin_works
    copy_in_config_dir("meaning_by_path")
    @installer.__reset_loader

    @installer.uninstall("inspec-meaning-of-life")

    # Plugins file entry should be removed
    plugin_json_path = File.join(ENV["INSPEC_CONFIG_DIR"], "plugins.json")
    plugin_json_data = JSON.parse(File.read(plugin_json_path))
    entries = plugin_json_data["plugins"].select { |e| e["name"] == "inspec-meaning-of-life" }
    assert_empty entries, "After path-based uninstall, plugin name should be removed from plugins.json"
  end

  def test_uninstall_a_gem_plugin
    skip_slow_tests # not that slow, just noisy

    copy_in_config_dir("test-fixture-1-float")
    @installer.__reset_loader

    capture_subprocess_io do
      @installer.uninstall("inspec-test-fixture")
    end

    # UnInstalling a gem physically removes the gemspec and the gem library code
    spec_path = File.join(@installer.gem_path, "specifications", "inspec-test-fixture-0.1.0.gemspec")
    refute File.exist?(spec_path), "After uninstallation of a gem plugin, the gemspec should be removed."
    installed_gem_base = File.join(@installer.gem_path, "gems", "inspec-test-fixture-0.1.0")
    refute Dir.exist?(installed_gem_base), "After uninstallation of a gem plugin, the gem tree should be removed."

    # Rubygems' idea of what we have installed should be changed.
    # It should no longer be able to satisfy a request for the formerly installed gem.
    universe_set = @installer.send(:build_gem_request_universe) # private method
    request_set = Gem::RequestSet.new(Gem::Dependency.new("inspec-test-fixture"))
    assert_raises(Gem::UnsatisfiableDependencyError) { request_set.resolve(universe_set) }

    # Plugins file entry should be removed
    config_file = Inspec::Plugin::V2::ConfigFile.new
    refute config_file.existing_entry?(:'inspec-test-fixture'), "After gem-based uninstall, plugin name should be removed from plugins.json"
  end

  def test_uninstall_a_gem_plugin_removes_deps
    skip_slow_tests # not that slow, just noisy

    copy_in_config_dir("test-fixture-2-float")
    @installer.__reset_loader

    capture_subprocess_io do
      @installer.uninstall("inspec-test-fixture")
    end

    # UnInstalling a gem removes the gemspec and the gem library code
    spec_path = File.join(@installer.gem_path, "specifications", "inspec-test-fixture-0.2.0.gemspec")
    refute File.exist?(spec_path), "After uninstallation of a gem plugin with deps, the gemspec should be removed."
    installed_gem_base = File.join(@installer.gem_path, "gems", "inspec-test-fixture-0.2.0")
    refute Dir.exist?(installed_gem_base), "After uninstallation of a gem plugin with deps, the gem tree should be removed."

    # UnInstalling a gem with dependencies should result in the deps being removed
    spec_path = File.join(@installer.gem_path, "specifications", "ordinal_array-0.2.0.gemspec")
    refute File.exist?(spec_path), "After uninstallation of a gem plugin with deps, the dep gemspec should be removed."
    installed_gem_base = File.join(@installer.gem_path, "gems", "ordinal_array-0.2.0")
    refute Dir.exist?(installed_gem_base), "After installation a gem plugin with deps, the gem tree should be removed."

    # Rubygems' idea of what we have installed should be changed.
    # It should no longer be able to satisfy a request for the formerly installed *dependency*
    universe_set = @installer.send(:build_gem_request_universe) # private method
    request_set = Gem::RequestSet.new(Gem::Dependency.new("ordinal_array"))
    assert_raises(Gem::UnsatisfiableDependencyError) { request_set.resolve(universe_set) }
  end

  # TODO: Able to uninstall a specific version of a gem plugin
  # TODO: Prevent removing a gem if it will lead to unsolveable dependencies
  # TODO: Allow removing a gem that will lead to unsolveable dependencies if :force is provided
end

#-----------------------------------------------------------------------#
# Searching
#-----------------------------------------------------------------------#
class PluginInstallerSearchTests < Minitest::Test
  include InstallerTestHelpers

  def setup
    # This is not ideal. I want to skip all of them, as it is the
    # first test that is slow, but I just debugged a really complex
    # interaction where if none of these tests are run, a whole slew
    # of other tests are trying to set up config under /var/empty
    # instead of our fixture dir. I don't have the knowhow to dig that
    # deep yet, but I do know how to make the tests pass even if that
    # is a bit slower.
    skip_slow_tests unless name =~ /omits_inspec_gem/ # the first test in particular has a ~2.5s hit

    super
  end

  def test_search_for_plugin_by_exact_name
    skip_live_net_tests

    results = @installer.search("inspec-test-fixture", exact: true)
    assert_kind_of Hash, results, "Results from searching should be a Hash"
    assert results.key?("inspec-test-fixture"), "Search results should have a key for the sought plugin"
    assert_equal 1, results.count, "There should be exactly one search result"
    version_list = results["inspec-test-fixture"]
    assert_includes version_list, "0.1.0", "Version list should contain 0.1.0"
    assert_includes version_list, "0.2.0", "Version list should contain 0.2.0"
  end

  def test_search_for_plugin_that_does_not_exist
    skip_live_net_tests

    results = @installer.search("inspec-test-fixture-nonesuch", exact: true)
    assert_empty results
  end

  def test_search_for_plugin_by_wildard
    skip_live_net_tests

    results = @installer.search("inspec-test-")
    assert_kind_of Hash, results, "Results from searching should be a Hash"
    assert results.key?("inspec-test-fixture"), "Search results should have a key for at least one plugin"
    version_list = results["inspec-test-fixture"]
    assert_includes version_list, "0.1.0", "Version list should contain 0.1.0"
    assert_includes version_list, "0.2.0", "Version list should contain 0.2.0"
  end

  def test_search_omits_inspec_gem_on_the_reject_list
    skip_slow_tests
    skip_live_net_tests

    results = @installer.search("inspec-")
    assert results.key?("inspec-test-fixture")

    # Here, 'inspec-core', 'inspec-multi-server'
    # are the names of real rubygems.  They are not InSpec/Train plugins, though,
    # and installing them would be a jam-up.
    # This is configured in 'etc/plugin_filters.json'.
    %w{
      inspec-core
      inspec-multi-server
    }.each do |plugin_name|
      refute results.key(plugin_name)
    end
  end

  def test_search_omits_train_gem_on_the_reject_list
    skip_live_net_tests

    results = @installer.search("train-")
    assert results.key?("train-test-fixture")

    # Here, train-tax-calculator'
    # is the name of a real rubygem.  It is not a InSpec/Train plugin, though,
    # and installing it would be a jam-up.
    # This is configured in 'etc/plugin_filters.json'.
    [
      "train-tax-calculator",
    ].each do |plugin_name|
      refute results.key(plugin_name)
    end
  end
end
