require File.dirname(__FILE__) + "/config"

module LayeredTemplate
  module Helper
    @@template_search_path = ENV['TEMPLATE_LOAD_PATH'] || Config.tpl_dir

    def find_templates(template_name)
      Dir["#{@@template_search_path}/#{template_name}/*"].select{|fname| fname =~ %r|\.erb$| }
    end
    module_function :find_templates

    def template_search_path(path)
      @@template_search_path = path
    end
  end
end
