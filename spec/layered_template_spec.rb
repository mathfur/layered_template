require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "LayeredTemplate" do
  before do
    @template = mock('Template', :t_attrs => {})
    @sandbox = Sandbox.new(@template)
  end

  it "'s haml_element should return indented string." do
single_line_sample = "%h2 title"
multi_line_sample = <<EOS
%h2 title
%p description
EOS
    @sandbox.send(:haml_element, single_line_sample, 2).should == "\n    %h2 title"
    @sandbox.send(:haml_element, multi_line_sample, 2).should == <<EOS.rstrip

    %h2 title
    %p description
EOS
  end

  it "'s haml_element translate 'r> ...' to '= ..'" do
    @sandbox.send(:haml_element, "r> title").should == "= title"
  end

  it "'s haml_element add one space to other string" do
    @sandbox.send(:haml_element, "title").should == " title"
  end
end
