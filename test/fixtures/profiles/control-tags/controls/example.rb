control "basic" do
  tag "tag1"
  tag severity: nil
  tag data: "tag2"
  tag data_arr: ["tag3", "tag4"]
  describe(true) { it { should eq true } }
end

control "tag keyword used in control name and tag value" do
  tag "tag5"
  describe(true) { it { should eq true } }
end

control "multiple tags in one line" do
  tag "tag6", "tag7", "tagname with space"
  tag data1: "tag8", data2: "tag9"
  tag data_arr1: ["tag10", "tag11"], data_arr2: ["tag12", "tag13"]
  describe(true) { it { should eq true } }
end

control "all different formats of tags in one line" do
  tag "tag14", data: "tag15", data_arr: ["tag16", "tag17"]
  describe(true) { it { should eq true } }
end

control "failure control" do
  tag "tag18"
  describe(true) { it { should eq false } }
end