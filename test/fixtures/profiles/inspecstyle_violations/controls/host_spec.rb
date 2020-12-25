# copyright: 2015, Chef Software, Inc

title 'Host example.com lookup'

control 'test01' do
  impact 0.5
  title 'Catchy title'
  desc 'example.com should always exist.'
  attribute('amplifier_max_volume', value: 10)
  describe host('example.com') do
    it { should be_resolvable }
  end
end
