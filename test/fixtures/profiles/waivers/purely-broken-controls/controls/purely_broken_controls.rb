control '01_my_broken_control' do
  raise 'Everything is destroyed as this has been run'
  describe true do
    it { should eq true }
  end
end

# This is a comment mentioning a control word

control '02_my_working_but_waived_control' do
  describe true do
    it { should eq true }
  end
end

control '03_my_working_control' do
  describe true do
    it { should eq true }
  end
end
