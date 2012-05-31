require File.dirname(__FILE__) + "/config"

module Helper
  @@template_search_paths = ENV['TEMPLATE_LOAD_PATH'] || []
  @@template_search_paths << Config.tpl_dir

  def find_template(template_name)
    @@template_search_paths.find do |path|
      Dir["#{path}/*"].find do |fname|
        return fname if fname =~ %r|/#{template_name}\.erb$|
      end
    end
  end
  module_function :find_template

  def prepend_template_search_path(paths)
    @@template_search_paths += [paths].flatten
  end
end
