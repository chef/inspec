# Vulcano CLI

Test your Server, VM, or workstation.

Small example: Write a your checks in `test.rb`:

```ruby
describe file('/proc/cpuinfo') do
  it { should be_file }
end

describe ssh_config do
  its('Protocol') { should eq('2') }
end
```

Run this file locally:

```bash
vulcano exec test.rb
```

## Installation

Requires Ruby ( >1.9 ).

To simply run it without installation, you must install [bundler](http://bundler.io/):

```bash
bundle install
bundle exec bin/vulcano help
```

To install it as a gem locally, run:

```bash
gem build vulcano.gemspec
gem install vulcano-*.gem
```

You should now be able to run:

```bash
vulcano --help
```

## Configuration

Run tests against different targets:

```bash
# run test locally
vulcano exec test.rb

# run test on remote host on SSH
vulcano exec test.rb -t ssh://user@hostname

# run test on remote windows host on WinRM
vulcano exec test.rb -t winrm://Administrator@windowshost --password 'your-password'

# run test on docker container
vulcano exec test.rb -t docker://container_id
```

## Custom resources

You can easily create your own resources. Here is a custom resource for an
application called Gordon and save it in `gordon_config.rb`:

```ruby
require 'yaml'

class GordonConfig < Vulcano.resource
  name 'gordon_config'

  def initialize
    @path = '/etc/gordon/config.yaml'
    @config = vulcano.file(@path).content
    @params = YAML.load(@config)
  end

  def method_missing(name)
    @params[name.to_s]
  end
end
```

Include this file in your `test.rb`:

```ruby
require_relative 'gordon_config'
```

Now you can start using your new resource:

```ruby
describe gordon_config do
  its('Version') { should eq('1.0') }
end
```

## Contributing

1. Fork it
1. Create your feature branch (git checkout -b my-new-feature)
1. Commit your changes (git commit -am 'Add some feature')
1. Push to the branch (git push origin my-new-feature)
1. Create new Pull Request


Copyright 2015 Chef Software Inc. All rights reserved.
Copyright 2015 Vulcano Security GmbH. All rights reserved.
Copyright 2015 Dominik Richter. All rights reserved.
