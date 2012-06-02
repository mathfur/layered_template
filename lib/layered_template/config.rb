module LayeredTemplate
  class Config
    @@base_dir = File.expand_path(File.dirname(__FILE__) + "/../..")
    def self.tpl_dir
      "#{@@base_dir}/template"
    end
  end
end

class ConfigForRunningDSL
  attr_reader :config

  def initialize
    @config = {}
  end

  def method_missing(name, value, &block)
    @config[name.to_sym] = value
  end
end
