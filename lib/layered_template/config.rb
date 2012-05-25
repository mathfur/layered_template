module Config
  @@base_dir = File.expand_path(File.dirname(__FILE__) + "/../..")
  def tpl_dir
    "#{@@base_dir}/template"
  end
  module_function :tpl_dir
end
