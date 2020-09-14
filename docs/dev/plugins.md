# Developing Chef InSpec Plugins for the v2 plugin API

## Introduction

### Inspiration

The software design of the Chef InSpec Plugin v2 API is deeply inspired by the Vagrant plugin v2 system. While the Chef InSpec Plugin v2 system is an independent implementation, acknowledgements are due to the Hashicorp team for such a well-thought-out design.

### Note About versions

"v2" refers to the second major version of the Plugin API. It doesn't refer to the Chef InSpec release number.

### Design Goals

* Load-on-demand. Improve `inspec` startup time by making plugins load heavy libraries only if they are being used.
* Independent velocity. Enable passionate community members to contribute at their own pace by shifting core development into plugin development.
* Increase dogfooding. Convert internal components into plugins to reduce core complexity and allow testing in isolation.

### Design Anti-goals

* Don't implement resources in plugins; use resource packs for that.

## How Plugins are Located and Loaded

### Plugins are usually gems

The normal distribution and installation method is via gems, handled by the `inspec plugin` command.

`inspec plugin install inspec-myplugin` will fetch `inspec-myplugin` from rubygems.org, and install it and its gemspec dependencies under the user's `.inspec` directory. You may also provide a local gemfile. For local development, however, path-to-source is usually most convenient.

For more on the `plugin` CLI command, run `inspec plugin help`.

### Plugins can be bundled with a profile

If plugin code is tightly coupled to one profile only, you can bundle it into the profile by placing it into the `libraries/` directory.

The plugin name must be prefixed with "profile" to handle loading properly.

### Plugins may also be found by path to a source tree

For local development or site-specific installations, you can also 'install' a plugin by path using `inspec plugin`, or edit `~/.inspec/plugins.json` directly to add a plugin.

### The plugins.json file

Chef InSpec stores its list of known plugins in a file, `~/.inspec/plugins.json`. The purpose of this file is avoid having to do a gem path filesystem scan to locate plugins. When you install, update, or uninstall a plugin using `inspec plugin`, Chef InSpec updates this file.

You can tell Chef InSpec to use a different config directory using the INSPEC_CONFIG_DIR environment variable.

Top-level entries in the JSON file:

 * `plugins_config_version`| must have the value "1.0.0". Reserved for future format changes.
 * `plugins`| an Array of Hashes, each containing information about plugins that are expected to be installed

Each plugin entry may have the following keys:

 * `name`| Required. String name of the plugin. Internal machine name of the plugin. Must match `plugin_name` DSL call (see Plugin class below).
 * `installation_type`| Optional, default "gem". Selects a loading mechanism, may be either "path" or "gem"
 * `installation_path`| Required if installation_type is "path". A `require` will be attempted against this path. It may be absolute or relative; Chef InSpec adds both the process current working directory as well as the Chef InSpec installation root to the load path.

TODO: keys for gem installations

Putting this all together, here is a plugins.json file from the Chef InSpec test suite:

```json
{
  "plugins_config_version" : "1.0.0",
  "plugins": [
    {
      "name": "inspec-meaning-of-life",
      "installation_type": "path",
      "installation_path": "test/fixtures/plugins/meaning_of_life_path_mode/inspec-meaning-of-life"
    }
  ]
}
```

### Plugin Runtime Configuration

You can read runtime configuration data from your user using `Inspec::Config.cached.fetch_plugin_config("your-plugin-name")`, which will return a hash with indifferent access representing the user's config file `plugins` section pertaining to your plugin. See [the config file](https://www.inspec.io/docs/reference/config/) for more information.

Do not store or read configuration information from plugins.json.

## Plugin Parts

### A Typical Plugin File Layout

```
inspec-my-plugin.gemspec
lib/
  inspec-my-plugin.rb  # Entry point
  inspec-my-plugin/
    cli.rb             # An implementation file
    plugin.rb          # Plugin definition file
    heavyweight.rb     # A support file
```

Generally, except for the entry point, you may name these files anything you like; however, the above example is the typical convention.

### Gemspec and Plugin Dependencies

This is a normal Gem specification file. When you release your plugin as a gem, you can declare dependencies here, and Chef InSpec will automatically install them along with your plugin.

If you are using a path-based install, Chef InSpec will not manage your dependencies.

### Entry Point

The entry point is the file that will be `require`d at load time (*not* activation time; see Plugin Lifecycle, below).  You should load the bare minimum here - only the plugin definition file. Do not load any plugin dependencies in this file.

```ruby
# lib/inspec-my-plugin.rb
require_relative 'inspec-my-plugin/plugin'
```

### Plugin Definition File

The plugin definition file uses the plugin DSL to declare a small amount of metadata, followed by as many activation hooks as your plugin needs.

While you may use any valid Ruby module name, we encourage you to namespace your plugin under `InspecPlugins::YOUR_PLUGIN`.

```ruby
# lib/inspec-my-plugin/plugin.rb
module InspecPlugins
  module MyPlugin
    # Class name doesn't matter, but this is a reasonable default name
    class Plugin < Inspec.plugin(2)

      # Metadata
      # Must match entry in plugins.json
      plugin_name :'inspec-my-plugin'

      # Activation hooks (CliCommand as an example)
      cli_command :'my-command' do
        require_relative 'cli'
        InspecPlugins::MyPlugin::CliCommand
      end

    end
  end
end
```

Note that the block passed to `cli_command` is not executed when the plugin definition is loaded. It will only be executed if inspec decides it needs to activate that plugin component.

Every activation hook is expected to return a `Class` which will be used in post-activation or execution phases. The behavior, duck typing, and superclass of that Class vary depending on the plugin type; see below for details.

### Implementation Files

Inside the implementation files, you should be sure to do three things:

1. Load any heavyweight libraries your plugin needs
2. Create a class (which you will return from the activator hook)
3. Within the class, implement your functionality, as dictated by the plugin type API

```ruby
# lib/inspec-my-plugin/cli.rb

# Load enormous dependencies
require_relative 'heavyweight'

module InspecPlugin::MyPlugin
  # Class name doesn't matter, but this is a reasonable default name
  class CliCommand < Inspec.plugin(2, :cli_command) # Note two-arg form
    # Implement API or use DSL as dictated by cli_command plugin type
    # ...
  end
end
```

## Plugin Lifecycle

All queries regarding plugin state should be directed to `Inspec::Plugin::V2::Registry.instance`, a singleton object.

```ruby
registry = Inspec::Plugin::V2::Registry.instance
plugin_status = registry[:'inspec-meaning-of-life']
```

### Discovery (Known Plugins)

If a plugin is mentioned in `plugins.json` or is a plugin distributed with Chef InSpec itself, it is *known*. You can get its status, a `Inspec::Plugin::V2::Status` object.

Reading the plugins.json file is handled by the Loader when Loader.new is called; at that point the registry should know about plugins.

### Loading

Next, we load plugins. Loading means that we `require` the entry point determined from the plugins.json. Your plugin definition file will thus execute.

If things go right, the Status now has a bunch of Activators, each with a block that has not yet executed.

If things go wrong, have a look at `status.load_exception`.

### Activation and Execution

Depending on the plugin type, activation may be triggered by a number of different events. For example, CliCommand plugin types are activated when their activation name is mentioned in the command line arguments.

After activation, code for that aspect of the plugin is loaded and ready to execute. Execution may be triggered by a number of different events. For example, the CliCommand plugin types are implicitly executed by Thor when `Inspec::CLI` calls `start()`.

Refer to the sections below for details about activation and execution timing.

## Implementing a CLI Command Plugin

The CliCommand plugin_type allows you to extend the Chef InSpec command line interface by adding a namespace of new commands. Chef InSpec is based on [Thor](http://whatisthor.com/) ([docs](https://www.rubydoc.info/github/wycats/thor/Thor)), and the plugin system exposes Thor directly.

CliCommand can do things like:

```bash
# A namespaced custom command with options
you@machine$ inspec sweeten add --kind sugar --teaspoons 2
# A namespaced custom command with short options
you@machine$ inspec sweeten add -k agave
# Mix global and namespace options
you@machine$ inspec --debug sweeten add -k aspartame
# Namespace included in help
you@machine$ inspec help
Commands:
  inspec archive PATH      # archive a profile to tar.gz (default) or zip
  inspec sweeten ...       # Add spoonfuls til the medicine goes down
# Detailed help
[cwolfe@lodi inspec-plugins]$ inspec help sweeten
Commands:
  inspec sweeten add [opts]       # Adds sweetener to your beverage
  inspec sweeten count            # Reports on teaspoons in your beverage, always bad news
```

Currently, it cannot create a direct (non-namespaced) command, such as `inspec mycommand` with no subcommands.

### Declare your plugin activators

In your `plugin.rb`, include one or more `cli_command` activation blocks. The activation block name will be matched against the command line arguments; if the name is present, your activator will fire (in which case it should load any needed libraries) and should return your implementation class.

#### CliCommand Activator Example

```ruby

# In plugin.rb
module InspecPlugins::Sweeten
  class Plugin < Inspec.plugin(2)
    # ... other plugin stuff

    cli_command :sweeten do
      require_relative 'cli.rb'
      InspecPlugins::Sweeten::CliCommand
    end
  end
end
```

Like any activator, the block above will only be called if needed. For CliCommand plugins, the plugin system naively scans through ARGV, looking for the activation name as a whole element. Multiple CliCommand activations may occur if several different names match, though each activation will only occur once.

```bash
you@machine $ inspec sweeten ... # Your CliCommand implementation is activated and executed
you@machine $ inspec exec ... # Your CliCommand implementation is not activated
```

Execution occurs implicitly via `Thor.start()`, which is handled by `bin/inspec`. Keep reading.

You should also be aware of one other activation event: if the CLI is invoked as `inspec help`, *all* CliCommand plugins will activate (but will not be executed). This is so that each plugin's help information can be registered with Thor.

### Implementation class for CLI Commands

In your `cli.rb`, you should begin by requesting the superclass from `Inspec.plugin`:

```ruby
module InspecPlugins::Sweeten
  class CliCommand < Inspec.plugin(2, :cli_command)
    # ...
  end
end
```

The Chef InSpec plugin v2 system promises the following:

* The superclass will be an (indirect) subclass of Thor
* The plugin system will handle registering the subcommand with Thor for you
* The plugin system will handle setup of the subcommand help message for you

### Implementing your command

Within your `cli.rb`, you need to do two things:

* Inform Chef InSpec of your subcommand's usage and description, so the `help` commands will work properly
* Implement your subcommands and options using the Thor DSL

See also: [Thor homepage](http://whatisthor.com/) and [Thor docs](https://www.rubydoc.info/github/wycats/thor/Thor).

#### Call subcommand_desc

Within your implementation, make a call like this:

```ruby
# Class declaration as above
subcommand_desc 'sweeten ...', 'Add spoonfuls til the medicine goes down'
```

The first argument is the usage message; it will be displayed whenever you execute `inspec help`, or when Thor tries to parse a malformed `inspec sweeten ...` command.

The second is the command groups description, and is displayed with `inspec help`.

Both arguments are free-form Strings intended for humans; the usage message should begin with your subcommand name to prevent user confusion.

If you neglect to call this DSL method, Thor will not register your command.

#### Adding Subcommands

The minimum needed for a command is a call to `desc` to set the help message, and a method definition named after the command.

```ruby
desc 'Reports on teaspoons in your beverage, always bad news'
def count
  # Someone has executed `inspec sweeten count`| do whatever that entails
  case beverage_type
  when :soda
    puts 12
  when :tea_two_lumps
    puts 2
  end
end
```

There is a great deal more you can do with Thor, especially concerning handling options. Refer to the Thor docs for more examples and details.

#### Using no_command

One common surprise seen with Thor is that every public instance method of your CliCommand implementation class is expected to be a CLI command definition. Thor will issue a warning if it encounters a public method definition without a `desc` call preceding it. Two ways around this include:

* Make your helper methods private
* Enclose your non-command methods in a no_command block (a feature of Thor just for this circumstance)

```ruby
no_command do
  def beverage_type
    @bevvy
  end
end
```

## Implementing Reporter Plugins

Reporter plugins offer the opportunity to customize or create entirely new output formats for Chef InSpec. Reporter plugins operate at the very end of the Chef InSpec run when all test data has finalized.

### Declare your plugin activators

In your `plugin.rb`, include one or more `reporter` activation blocks. The activation block name will be matched against the value passed into the `--reporter` option. If a match occurs, your activator will fire, which loads any needed libraries, and return your implementation class.

#### Reporter Activator Example

```ruby

# In plugin.rb
module InspecPlugins::Sweeten
  class Plugin < Inspec.plugin(2)
    # ... other plugin stuff

    reporter :sweet do
      require_relative 'reporter.rb'
      InspecPlugins::Sweeten::Reporter
    end
  end
end
```

Like any activator, the block above will only be called if needed. For Reporter plugins, the plugin system examines the `--reporter` argument, or the `reporter:` JSON config option, and looks for the activation name as a prefix. Multiple Reporter activations may occur if several different names match, though each activation will only occur once.

```bash
you@machine $ inspec exec --reporter sweet # Your Reporter implementation is activated and executed
you@machine $ inspec exec --reporter json  # Your Reporter implementation is not activated
```

### Implementation class for Reporters

In your `reporter.rb`, you should begin by requesting the superclass from `Inspec.plugin`:

```ruby
module InspecPlugins::Sweeten
  class Reporter < Inspec.plugin(2, :reporter)
    def render
      # examine run_data and call output()
    end
    def self.run_data_schema_constraints
      "~> 0.0" # Accept any non-breaking change
    end
  end
end
```

### Implementing your Reporter

#### Implement render()

The primary responsibility you must fulfill is to implement render. Typically, you will examine the `run_data` structure (documented below), which is provided as an accessor. Call `output(String, newline_wanted = true)` to send output.

#### Implement self.run_data_schema_constraints

The run_data API is versioned. Your plugin should declare which version(s) it is compatible with by implementing a simple class method, which should return a GemSpec-like constraint. Currently, a simple warning is issued if a version mismatch occurs.

The run_data version scheme follows a data-oriented SemVer approach:
 * bump patch: fixing a bug in the provenance or description of a data element, no key changes
 * bump minor: adding new data elements
 * bump major: deleting or renaming data elements

Prior to version 1.0.0, the API is considered unstable, as per SemVer. The current plan is to bump the major version to 1.0.0 when all of the existing core reporters have been migrated to plugins. It is probable that new data elements and new Hash compatibility behavior will be added during the core reporter plugin conversion process.

#### The run_data structure

The `run_data` object contains all data from the Chef InSpec run. Here is an overview of this object:

| Field | Description |
|-------|-------------|
|`run_data.controls`| Array of Control records. Flattened copy of those found in |`run_data.profiles[*].controls[*]`. See there for details.|
|`run_data.platform.name`| String, name of the OS/API that the run targeted.|
|`run_data.platform.release`| String, version number of the OS/API that the run targeted.|
|`run_data.platform.target`| String, target URI|
|`run_data.profiles`| Array of Profile records|
|`run_data.profiles[0].controls`| Array of Control records|
|`run_data.profiles[0].controls[0].code`| String, source code of the control|
|`run_data.profiles[0].controls[0].desc`| String, concatenated copy of all desc tags|
|`run_data.profiles[0].controls[0].descriptions`| Hash, Symbol => String, collection of all the `desc` tags.|
|`run_data.profiles[0].controls[0].id`| String, ID (name) of the control|
|`run_data.profiles[0].controls[0].impact`| Float, severity of the control range 0.0 .. 1.0|
|`run_data.profiles[0].controls[0].refs`| Array of Ref records for `ref` tags|
|`run_data.profiles[0].controls[0].refs[0].ref`| String, human meaningful reference|
|`run_data.profiles[0].controls[0].refs[0].url`| String, URL for reference|
|`run_data.profiles[0].controls[0].results`| Array of Result records, which represent Describe blocks|
|`run_data.profiles[0].controls[0].results[0].backtrace`| Array of Strings, stacktrace if an error occurred.|
|`run_data.profiles[0].controls[0].results[0].code_desc`| String, generated complete description of the test|
|`run_data.profiles[0].controls[0].results[0].exception`| String, name of an exception thrown (if any)|
|`run_data.profiles[0].controls[0].results[0].expectation_message`| String, generated phrase like "is expected to equal 2"|
|`run_data.profiles[0].controls[0].results[0].message`| String, human-friendly text present when test has failed"|
|`run_data.profiles[0].controls[0].results[0].resource`| Undocumented and usually unpopulated; try exploring resource_title |
|`run_data.profiles[0].controls[0].results[0].resource_name`| String, name of the resource used in the test|
|`run_data.profiles[0].controls[0].results[0].resource_title`| Anonymous Class, the actual instance of the Resource. Responds to to_s with the name of the resource.|
|`run_data.profiles[0].controls[0].results[0].run_time`| Float, execution time in seconds for the test|
|`run_data.profiles[0].controls[0].results[0].skip_message`| String, if the test was skipped, explains why (user provided)|
|`run_data.profiles[0].controls[0].results[0].start_time`| DateTime, time the test started executing|
|`run_data.profiles[0].controls[0].results[0].status`| String, one of "passed", "failed", or "skipped".|
|`run_data.profiles[0].controls[0].source_location.line`| Integer, line number of source code where control begins|
|`run_data.profiles[0].controls[0].source_location.ref`| String, relative path to file in which source code resides|
|`run_data.profiles[0].controls[0].tags`| Hash, String => String, collection of `tag`s.|
|`run_data.profiles[0].controls[0].title`| String, optional title of control.|
|`run_data.profiles[0].controls[0].waiver_data.expiration_date`| DateTime, time at which the waiver expires if any|
|`run_data.profiles[0].controls[0].waiver_data.justification`| String, user-provided reason for applying the waiver|
|`run_data.profiles[0].controls[0].waiver_data.run`| Boolean, whether the control should run even if waivered|
|`run_data.profiles[0].controls[0].waiver_data.skipped_due_to_waiver`| Boolean, whether the control was marked `skipped` due to the |waiver system
|`run_data.profiles[0].controls[0].waiver_data.message`| Reserved|
|`run_data.profiles[0].copyright`| String, Copyright text from inspec.yml|
|`run_data.profiles[0].copyright_email`| String, Copyright email from inspec.yml|
|`run_data.profiles[0].depends`| Array of Dependency records|
|`run_data.profiles[0].depends[0].branch`| branch name if it was a git reference|
|`run_data.profiles[0].depends[0].commit`| commit ref if it was a git reference|
|`run_data.profiles[0].depends[0].compliance`| String, "user/profilename" on Automate server if it was an Automate reference|
|`run_data.profiles[0].depends[0].git`| location of dependent profile if it was a git reference|
|`run_data.profiles[0].depends[0].name`| name (assigned alias) of dependent profile|
|`run_data.profiles[0].depends[0].path`| location of dependent profile if it was a local reference|
|`run_data.profiles[0].depends[0].relative_path`| relative path within clone if it was a git reference|
|`run_data.profiles[0].depends[0].status_message`| Reason if status is "failed" or "skipped"|
|`run_data.profiles[0].depends[0].supermarket`| String, "user/profilename" on Supermarket server if it was a Supermarket reference|
|`run_data.profiles[0].depends[0].status`| String, one of "loaded", "failed" or "skipped"|
|`run_data.profiles[0].depends[0].tag`| tag ref if it was a git reference|
|`run_data.profiles[0].depends[0].version`| semver tag if it was a git reference|
|`run_data.profiles[0].depends[0].url`| location of dependent profile if it was a URL reference|
|`run_data.profiles[0].groups`| Array, of Group records, describing the files that contained controls|
|`run_data.profiles[0].groups[0].controls`| Array of Strings, the IDs of the controls in the file|
|`run_data.profiles[0].groups[0].id`| String, typically a relative path like `controls/myfile.rb`|
|`run_data.profiles[0].groups[0].title`| String, value of a `title` DSL command in the file|
|`run_data.profiles[0].inputs`| Array of Input records describing inputs present in profile|
|`run_data.profiles[0].inputs[0].name`| String name of Input|
|`run_data.profiles[0].inputs[0].options.required`| Boolean, whether input was required.|
|`run_data.profiles[0].inputs[0].options.sensitive`| Boolean, true if the value of the input has been replaced with "***" |
|`run_data.profiles[0].inputs[0].options.type`| String, type constraint on input, if any|
|`run_data.profiles[0].inputs[0].options.value`| Value of Input|
|`run_data.profiles[0].license`| String, name of license for the profile|
|`run_data.profiles[0].maintainer`| String, name of the maintainer|
|`run_data.profiles[0].name`| String, machine name of the profile|
|`run_data.profiles[0].parent_profile`| String, name of the parent profile if this is a dependency|
|`run_data.profiles[0].sha256`| String, checksum of the profile|
|`run_data.profiles[0].status_message`| String, message indicating why the profile was not loaded if status is "failed" or "skipped"|
|`run_data.profiles[0].summary`| String,  A one-line summary from the inspec.yml|
|`run_data.profiles[0].supports`| Array of Support records indicating platform support|
|`run_data.profiles[0].supports[0].platform_family`| Platform restriction by family|
|`run_data.profiles[0].supports[0].platform_name`| Platform restriction by name|
|`run_data.profiles[0].supports[0].platform`| Platform restriction by name|
|`run_data.profiles[0].supports[0].release`| Platform restriction by release|
|`run_data.profiles[0].status`| String, one of "loaded", "failed" or "skipped"|
|`run_data.statistics.controls.failed.total`| Integer, total count of failing controls|
|`run_data.statistics.controls.passed.total`| Integer, total count of passing controls|
|`run_data.statistics.controls.skipped.total`| Integer, total count of passing controls|
|`run_data.statistics.controls.total`| Integer, total count of controls|
|`run_data.statistics.duration`| Float, time in seconds for the execution of Resources.|
|`run_data.version`| A String, such as "4.18.108" representing the Chef InSpec version.|

#### RunData Structure ChangeLog

v0.1.0 - Initial version
v0.2.0 - added `run_data.profiles[0].inputs[0].options.sensitive`

## Implementing Input Plugins

Input plugins provide values for Chef InSpec Inputs - the parameters you can place within profile control code.

For example, you might implement an Input plugin to fetch vales from a key-value store, such as `etcd`.

Input plugins have a simple API which is intended to be easy to adapt to a number of input backend implementations.

### Declare your input plugin activators

Generally speaking, an input plugin will only need to have one activator.

In your `plugin.rb`, include one or more `input` activation blocks. The activation block will fire when the InputRegistry is initialized, at which time case it should load any needed libraries and should return your implementation class.

The Input subsystem always activates all activators.

#### Input Activator Example

```ruby

# In plugin.rb
module InspecPlugins::Sweeten
  class Plugin < Inspec.plugin(2)
    # ... other plugin stuff

    input :coffee_fixins_bar do
      require_relative 'input.rb'
      InspecPlugins::Sweeten::Input
    end
  end
end
```

The Input subsystem always activates all activators when InputRegistry is initialized. Future work may enable us to dynamically load plugins; but we need to poll plugins when any input value is used.

### Implementation class for Input plugins

In your `input.rb`, you should begin by requesting the superclass from `Inspec.plugin`:

```ruby
module InspecPlugins::Sweeten
  class Input < Inspec.plugin(2, :input)
    # ...
  end
end
```

### Implementing your Input plugin

Within your implementation, you need to implement 2 mandatory methods and two optional methods.

#### default_priority

Optional, returns an integer 0-100, default 60. This value determines precedence when multiple input providers supply a value; higher values lend more precedence.

#### list_inputs(profile_name)

Mandatory. Given a String profile name, return an Array of String input names that may be fetched from this plugin. This may be used to optimize calls to fetch().

#### fetch(profile_name, input_name)

Mandatory. Given a String profile_name and String input_name, return the input value (whatever that means for your plugin).

#### Using a constructor to get config values

Optional. Implement `initialize()` to perform any startup tasks such as authorization. You can get to the InSpec config settings via `Inspec::Config.cached[some_key]`.

#### Implementation example

```ruby
module InspecPlugins::Sweeten
  class Input < Inspec.plugin(2, :input)

    def default_priority
      99 # Extremely opinionated
    end

    def fetch(profile_name, input_name)
      return nil unless profile_name = 'coffee_shop'

      case input_name
      when 'sugar'
        'delicious raw sugar in an eclectic brown packet'
      when "sweet'n'low"
        'how can you even do that to yourself'
      end
    end

    def list_input_names
      ['sugar',"sweet'n'low"]
    end
  end
end
```

## Implementing DSL Plugins

A DSL is a _domain specific language_, or a set of keywords you can use to write Chef InSpec profiles and resources more fluently.

Chef InSpec offers several DSLs:

* The Profile DSL, which is the set of keywords you use when writing profiles. The Profile DSL is internally divided into:
  * The Outer Profile DSL: those keywords which may appear in a Profile `controls/my-controls.rb` outside of a `control` or `describe` block
  * The Control DSL: those keywords which may appear in `control` block
  * The Describe DSL: those keywords which may appear within a `describe` block
  * The Test DSL: those keywords available within an `it`/`its` block
* The Resource DSL: those keywords which may be used when authoring a resource

Correspondingly, there are 4 plugin types in play here: `outer_profile_dsl`, `control_dsl`, `describe_dsl`, `test_dsl`, and `resource_dsl`.

DSL plugins let you alter the Chef InSpec profile authoring experience in a fundamental way.  For example, if you wish Chef InSpec had a way of expressing that some minimum of a set of tests must pass, but you don't care which, you could implement a `control_dsl` plugin named `threshold`:

```ruby
# in a hypothetical control file

# This control will pass if at least 2
# out of the describe blocks pass
control 'Like Meatloaf Sings' do
  threshold(2) do
    describe 'I want you' do
      it { should be_true }
    end

    describe 'I need you' do
      it { should be_true }
    end

    describe 'I love you' do
      it { should be_true }
    end
  end
end
```

### Activation Discipline For DSL Plugins

As DSL keywords are actually method calls, the activation system for the four DSL types is handled by `method_missing`.  For example, if you have registered a `control_dsl` activation hook named `threshold`, when Chef InSpec evaluates the code above and encounters the unknown method `threshold`, Chef InSpec will check for a `control_dsl` hook with that name, and if found, activate the hook, and then include the resulting module into that and all future controls. Once the module is loaded and included, future calls bypass the activation and loading mechanism entirely (because the `threshold` method is now defined, we never hit the `method_missing` that watches for activations).

The Outer Profile DSL, Control DSL, Describe DSL, Test DSL, and Resource DSL plugin types all have the same basic mechanism; only the scope of their activation varies.

### Defining DSL Plugin Activation Hooks

In your `plugin.rb`, include one or more `outer_profile_dsl`, `control_dsl`, `describe_dsl`, or `resource_dsl` activation blocks. A DSL activation block *must* do two things (though it may do more):

 * Return a Module that will be used as a mixin to the file, control, describe block, or resource
 * Require any files needed to support returning the implementation module.  It's important to require any support files in the activation block, not in the plugin definition; this allows Chef InSpec to only load files as they are needed.

Continuing the above example, one would declare the `threshold` Control DSL activation hook as follows:

```ruby
# in plugin.rb
module InspecPlugins::ThresholdDSL
  class Plugin < Inspec.plugin(2)
    plugin_name :'inspec-dsl-threshold'

    control_dsl :threshold do
      require 'inspec-dsl-threshold/control_dsl'
      # most plugins expect you to return a class name;
      # but DSL plugins must return a Module, because it
      # will be used as a mixin.
      InspecPlugins::ThresholdDSL::ThresholdControlDSL
    end

  end
end
```

### Implementing DSL Methods

Because each DSL plugin type is loaded into a specific context, each method defined in the mixin module you provide will have a specific parent class and state.

*Note*: these areas are deep within the internals of Chef InSpec and RSpec.  Documentation and stability of these interfaces will vary.
It is recommended to pin your dependency on `inspec` rather tightly, so you can test for compatibility issues prior to your users.
The Chef InSpec project does not consider the internal interfaces exposed to the DSL plugins to be part of the public interface, and thus may introduce breaking changes at anytime.  In other words, SemVer doesn't apply here, and you should likely use an exact pin.

#### Outer Profile DSL Context

When your mixin method is called, `self` will be an instance of an anonymous class representing the profile context being executed; each profile context gets its own anonymous class. No inheritance tree is provided; all meaningful functionality arrives through other DSL methods included.

One useful thing you can do is create macros for generating controls: the `control` DSL keyword is available to you, so you can call it as you see fit to create new controls.

#### Control DSL Context

When your mixin method is called, `self` will be an instance of an anonymous class representing the control being executed; each control gets its own anonymous class. The parent class of the anonymous class will be [Inspec::Rule](https://github.com/inspec/inspec/blob/master/lib/inspec/rule.rb), which is the internal name of a Control.  Please refer to the source for details on methods and instance variables.

#### Describe DSL Context

Describe DSL mixin methods will be attached as *class* methods to [RSpec::Core::ExampleGroup](https://github.com/rspec/rspec-core/blob/master/lib/rspec/core/example_group.rb).  Internally, 'describe' blocks are subclasses of the ExampleGroup class.  Please see the source of ExampleGroup for details about how describe blocks are evaluated.

Within your mixin method, you have access the methods RSpec uses to manage an ExampleGroup.  For example, `examples` returns an array of tests (`it`/`its` blocks) that have been encountered in the describe block prior to the invocation of your method; and `metadata` returns a hash of information about the describe block, including description and source code location.

#### Test DSL Context

Test DSL mixin methods will be attached as *instance* methods to [RSpec::Core::ExampleGroup](https://github.com/rspec/rspec-core/blob/master/lib/rspec/core/example_group.rb).  Internally, `it`/`its` blocks are evaluated in the context of an instance which is a subclass of the ExampleGroup class.  Please see the source of ExampleGroup for further details.

These blocks are called Examples in RSpec terminology. Chef InSpec treats Examples as tests, and sends tests and controls to the reporter engine; note that describe block are effectively ignored.

Within your mixin method, you have access the methods RSpec uses to manage an Example. You have access to the testing predicates (such as `should`), but also all Chef InSpec resources are available by name. Some useful class methods include `self.class.example_group`, which returns the example group are a member of; and `self.class.metadata` returns a hash of information about the test block, including description and source code location.

#### Resource DSL

Within a Resource DSL method, `self` will be the Class of a Resource that is currently being defined.  Your superclass will be whatever was returned by Inspec.resource(API_VERSION), which will typically be Inspec::Resource.

Resource DSL methods are especially useful for defining macros: adding properties and matchers to a resource.

### Implementation Module Layout Notes

#### Implementing multiple DSL methods of the same type in one Module

You may implement as many DSL methods as you see fit.  You may choose to be fine-grained, and load each individually from separate modules contained in separate files.

If you believe that using one of your suite of DSL methods implies that the user would be likely to use all of your suite, you may choose to implement them all in one mixin.  This saves on loading and activations.

That might look like:

```ruby
# in plugin.rb
module InspecPlugins::ColorDSL
  class Plugin < Inspec.plugin(2)
    plugin_name :'inspec-dsl-colors'

    control_dsl :red do
      require 'inspec-dsl-threshold/roygbiv'
      InspecPlugins::ColorDSL::RoyGBiv
    end

    control_dsl :orange do
      require 'inspec-dsl-threshold/roygbiv'
      InspecPlugins::ColorDSL::RoyGBiv
    end

    # etc... ... and yes, you could do that in a loop
  end
end
```

Now, when a user says `red` or `orange`, the entire suite of DSL methods will be loaded and included.

#### Implementing multiple DSL methods of the different types in one Module

For the brave, one may also choose to use the same implementation mixin with different types of activation hook.  This has serious implications for the code inside your DSL methods; depending on which context you are in, your class hierarchy (and thus instance methods and variables) may change dramatically.

For DSL plugins that are fairly simple - perhaps adding annotations or having a simple runtime side-effect - this may be a wise choice to avoid duplicating code.  However, DSL methods that are very interested in the state of their context will be obliged to rely on a fair bit of conditionals and introspection.

That might look like:

```ruby
# in plugin.rb
module InspecPlugins::ColorDSL
  class Plugin < Inspec.plugin(2)
    plugin_name :'inspec-dsl-colors'

    # Install the `red` DSL method at every available place within profiles
    # (with the same implementation!)
    outer_profile_dsl :red do
      require 'inspec-dsl-threshold/red'
      InspecPlugins::ColorDSL::Red
    end

    control_dsl :red do
      require 'inspec-dsl-threshold/red'
      InspecPlugins::ColorDSL::Red
    end

    describe_dsl :red do
      require 'inspec-dsl-threshold/red'
      InspecPlugins::ColorDSL::Red
    end

    test_dsl :red do
      require 'inspec-dsl-threshold/red'
      InspecPlugins::ColorDSL::Red
    end

  end
end
```

This approach may make sense among the four Profile DSLs; however the Resource DSL is quite different, and is unlikely to respond well to such an approach.
