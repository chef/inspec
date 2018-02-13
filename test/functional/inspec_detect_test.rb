require 'functional/helper'

describe 'inspec detect' do
  include FunctionalHelper

  it 'outputs the correct data' do
    res = inspec('detect')
    res.stderr.must_equal ''
    res.exit_status.must_equal 0

    stdout = res.stdout
    stdout.must_include "\n== Platform Details\n\n"
    stdout.must_include "\nName:      \e[0;36m"
    stdout.must_include "\nFamilies:  \e[0;36m"
    stdout.must_include "\nArch:      \e[0;36m"
    stdout.must_include "\nRelease:   \e[0;36m"
  end

  it 'outputs the correct data when `--format json` is used' do
    res = inspec('detect --format json')
    res.stderr.must_equal ''
    res.exit_status.must_equal 0

    json = JSON.parse(res.stdout)
    json.keys.must_include 'name'
    json.keys.must_include 'families'
    json.keys.must_include 'arch'
    json.keys.must_include 'release'
  end

  it 'outputs the correct data when target is an api' do
    res = inspec('detect -t aws://')
    res.stderr.must_equal ''
    res.exit_status.must_equal 0

    stdout = res.stdout
    stdout.must_include "\n== Platform Details\n\n"
    stdout.must_include "\nName:      \e[0;36m"
    stdout.must_include "\nFamilies:  \e[0;36m"

    stdout.wont_include "\nArch:"
    stdout.wont_include "\nRelease:"
  end
end
