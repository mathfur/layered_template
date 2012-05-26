# -*- encoding: utf-8 -*-

require "lib/layered_template/config"
require "lib/layered_template/helper"

require 'rubygems'
require "active_support"
require 'active_support/core_ext/array'
require 'erb'
require "getoptlong"

BASE_DIR = File.dirname(__FILE__) + "/.."

class LayeredTemplate
  def initialize(&block)
    @tables = []
    self.instance_eval(&block) if block_given?
  end

  def self.load(fname)
    instance = self.new
    instance.instance_eval(File.read(fname))
    instance
  end

  def table(name, &block)
    @tables << Table.new(self, name, &block)
  end

  def find_table(name)
    @tables.find{|t| t.name == name} or raise "The table '#{name}' is not found."
  end

  def output(dir=nil)
    @tables.map{|dc| dc.output(dir)}.join
  end
end

class Table
  attr_reader :name

  def initialize(parent, name, &block)
    @name = name
    @templates = []
    @tpl_opt = {}
    @tables = []
    @parent = parent
    self.instance_eval(&block)
  end

  def location(fname, location_id=nil)
    @tpl_opt[:fname] = fname
    @tpl_opt[:loc_id] = location_id
  end

  def enum(enum_in, enum_out)
    @tpl_opt[:enum_in] = enum_in
    @tpl_opt[:enum_out] = enum_out
  end

  def template(template_name, &block)
    @templates << Template.new(self, @name, template_name, @tpl_opt, &block)
    @tpl_opt = {}
  end
  alias_method :deploy, :template

  def attrs(labels, &block)
    db_attr_block = DbAttrBlock.new(labels, &block)
    @templates.map{|t| t.db_attr_block = db_attr_block}
  end

  def output(dir=nil)
    @templates.map{|t| t.output(dir)}.join
  end

  def table(name, &block)
    @tables << Table.new(self, name, &block)
  end

  def find_table(name)
    @tables.find{|table| table.name == name} || @parent.find_table(name)
  end
end

class Template
  # Name :: String
  # DeployTarget
  # TemplateAttrBlock

  attr_accessor :db_attr_block

  def initialize(table, name, template_name, opt={}, &block)
    @table = table
    @name = name
    @elems = []
    @opt = {}
    @template_fname = Helper.find_template(template_name) or raise "The template file does not found."
    self.instance_eval(&block)
  end

  def method_missing(name, *args)
    opts = args.extract_options!
    @elems << [name.to_sym, args.map{|a| Value.new(a)}, opts]
  end

  def output(dir=nil)
    sandbox = Sandbox.new(@table, @elems, db_attr_block)
    erb_result = ERB.new(File.read(@template_fname), nil, '-').result(sandbox.instance_eval("binding"))
    if @opt[:fname] && dir
      OutputManager.push("#{dir}/#{fname}", @opt[:loc_id], erb_result)
      nil
    else
      erb_result
    end
  end
end

class Sandbox
  attr_reader :t_attrs, :db_attrs
  def initialize(table, template_attrs, db_attrs, opt={})
    @table = table
    @t_attrs = template_attrs
    @db_attrs = db_attrs || []
    @enum = (opt[:enum_in] && opt[:enum_out])
    @enum_in = opt[:enum_in] || "objs"
    @enum_out = opt[:enum_out] || "obj"

    self.class.class_eval do
      template_attrs.each do |name, args, opts|
        unless respond_to?(name)
          define_method name do
            t_attrs.select{|name_, _, _| name == name.to_sym}.each do |name, args, hash|
              args.each{|arg| render(arg)}
            end
          end
        end
      end
    end
  end

  # nameという名前のテーブルを描画する
  def tbl(name)
    @table.find_table(name).output
  end

  # 頭文字r>などによって加工する
  def filter(str)
    str
  end

  # argの型に応じてテキストに変換する
  def render(arg)
    case arg.type
    when :table_or_attr
      if (attr = db_attrs.find{|name, args, hash| name == arg.v})
        attr.last[:val] || ""
      else
        tbl(arg.v)
      end
    when :source
      filter arg.v
    else
      raise ArgumentError, "#{arg.inspect} must be :table_or_attr or :source"
    end
  end

  # enum定義がされているときのみ
  # ループを回す
  def enum_wrap(&block)
    # TODO: 以下はどうなる?
    # * 「enum_wrapで囲まれた要素の前後にstrを挿入」ができない
    block.call
  end

  def before
    # TODO: あとで実装
  end

  def after
    # TODO: あとで実装
  end
end

class DbAttrBlock
  # [DbAttr]
  attr_accessor :elems

  def initialize(labels, &block)
    @labels = labels
    @elems = []
    self.instance_eval(&block)
  end

  def method_missing(name, *args)
    opts = args.extract_options!
    @elems << [name, args, Hash[*(@labels.map(&:to_sym).zip(args)).flatten]]
  end
end

class Value
  attr_reader :v, :type
  def initialize(v)
    @v = v
    @type = case v
    when String
      :source
    when Symbol
      :table_or_attr
    else
      :other
    end
  end
end

class OutputManager
  @@contents = {}

  def self.push(fname, loc_id, content)
    @contents[fname] ||= {}
    @contents[fname][loc_id] ||= []
    @contents[fname][loc_id] << content
  end

  def self.write_to_file
    @contents.each do |fname, hash|
      raise "現状ではfnameが存在した場合は上書きしない. fname: #{fname}" if File.exist?(fname)
      open(fname, 'w') do |f|
        f.write hash.map do |loc_id, contents|
<<EOS
content_for :#{loc_id} do
  #{contents.join("\n")}
EOS
        end.join("\n\n")
      end
    end
  end
end

parser = GetoptLong.new

parser.set_options(
  ['--template-path', '-t', GetoptLong::OPTIONAL_ARGUMENT],
  ['--verbose', GetoptLong::NO_ARGUMENT]
)

parser.each_option do |name, arg|
  case name
  when '--template-path', '-t'
    Helper.prepend_template_search_path(arg.split(/,/))
  end
end

ARGV = ["spec/sample/sample2.ltpl"]

raise "Missing ltpl argument" if ARGV.length != 1

ltpl_name = "#{Dir.pwd}/#{ARGV.shift}"
raise "Template file #{ltpl_name} is not exist." unless File.exist?(ltpl_name)

puts LayeredTemplate.load(ltpl_name).output(BASE_DIR)
