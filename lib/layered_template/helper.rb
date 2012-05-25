require "lib/layered_template/config"

module Helper
  @@template_load_paths = ENV['TEMPLATE_LOAD_PATH'] || []
  @@template_load_paths << Config.tpl_dir

  def find_template(template_name)
    @@template_load_paths.find do |path|
      Dir["#{path}/*"].find do |fname|
        fname =~ %r|/#{template_name}(\.[^\.]*)*$|
        return fname
      end
    end
  end
  module_function :find_template
end
