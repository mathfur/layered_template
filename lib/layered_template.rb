# -*- encoding: utf-8 -*-

require "lib/layered_template/config"

require 'rubygems'
require "active_support"
require 'active_support/core_ext/array'
require 'erb'


#class DeployTarget
#  # name
#  # (path, location_property) :: Maybe String
#end
#
#class Attr
#  # 名前 :: String
#  # {String => Object}
#
#  def initialize(name, hash = {})
#    @name = name
#    @hash = hash
#  end
#end
#
#class TemplateAttr < Attr
#  # super
#  # [DeployTarget]
#  def initialize(name, tables, hash)
#    super(name, hash)
#    @tables = tables
#  end
#end

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
    @tables << Table.new(name, &block)
  end

  def output(dir)
    @tables.map{|dc| dc.output(dir)}.join
  end
end

class Table
  # [Deploy]
  # DbAttrBlock
  attr_reader :name

  def initialize(name, &block)
    @name = name
    @templates = []
    @tpl_opt = {}
    @@all_tables = [self]
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
    @templates << Template.new(@name, template_name, @tpl_opt, &block)
    @tpl_opt = {}
  end
  alias_method :deploy, :template

  def attrs(labels, &block)
    db_attr_block = DbAttrBlock.new(labels, &block)
    @templates.map{|t| t.db_attr_block = db_attr_block}
  end

  def output(dir)
    @templates.map{|t| t.output(dir)}.join
  end

  def self.find(name)
    @all_tables.find{|t| t.name == name}
  end
end

class Template
  # Name :: String
  # DeployTarget
  # TemplateAttrBlock

  attr_accessor :db_attr_block

  def initialize(name, template_name, opt={}, &block)
    @name = name
    @elems = []
    @opt = {}
    template_fname = "#{Config.tpl_dir}/#{template_name}"

    if File.exist?(template_fname)
      @template_fname = template_fname
    else
      unless ["", ".html", ".js", ".css"].any? { |ext| (path = "#{template_fname}#{ext}.erb") && File.exist?(path) && (@template_fname = path) }
        raise "The template file '#{template_fname}' does not exist."
      end
    end
    self.instance_eval(&block)
  end

  def method_missing(name, *args)
    opts = args.extract_options!
    @elems << [name.to_sym, args.map{|a| Value.new(a)}, opts]
  end

  def output(dir)
    sandbox = Sandbox.new(@elems, db_attr_block.elems)
    erb_result = ERB.new(File.read(@template_fname), nil, '-').result(sandbox.instance_eval("binding"))
    return erb_result unless @opt[:fname]
    OutputManager.push("#{dir}/#{fname}", @opt[:loc_id], erb_result)
    nil
  end
end

class Sandbox
  attr_reader :t_attrs, :db_attrs
  def initialize(template_attrs, db_attrs, opt={})
    @t_attrs = template_attrs
    @db_attrs = db_attrs
    @enum = (opt[:enum_in] && opt[:enum_out])
    @enum_in = opt[:enum_in] || "objs"
    @enum_out = opt[:enum_out] || "obj"

    self.class.class_eval do
      template_attrs.each do |name, args, opts|
        unless respond_to?(name)
          define_method name do
            attr
          end
        end
      end
    end
  end

  # nameという名前のテーブルを描画する
  def tbl(name)
    Table.find(name).output
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
        tbl(arg)
      end
    when :source
      filter arg
    else
      raise ArgumentError
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

ltpl_name = "#{File.dirname(__FILE__)}/../spec/sample/sample1.ltpl"
raise "Template file #{ltpl_name} is not exist." unless File.exist?(ltpl_name)

BASE_DIR = File.dirname(__FILE__) + "/.."
puts LayeredTemplate.load(ltpl_name).output(BASE_DIR)

__END__
# まずデータ構造を決定 -> 付随する形でDSL定義

require "active_support"

#class MatrixedTree
#  def initialize(&block)
#    @tables = []
#    self.instance_eval(&block)
#  end
#
#  def table(&block)
#    @tables << Table.new(&block)
#  end
#
#  def tables(&block)
#    @tables.map { |t| block.call(Wrap.new(t)) }
#  end
#end

#module FooHelper
#  def l2i(str, *targets)
#    targets.each do |target|
#      str.gsub(/\b#{target}\b/){ "@#{target}" }
#    end
#  end
#end

module Layered
  class AbstractTable
    def _
      :default
    end
  end

  class Table < AbstractTable
    attr_reader :template_name, :tables, :name

    def initialize(name, &block)
      @name = name.to_s
      @attrs = {}
      @deploys = {}
      @tables = []
      self.instance_eval(&block) if block_given?
    end

    def template(name, &block)
      @template_name = name
      @template = Temlate.build(&block)
    end

    def attrs(labels, &block)
      @tables += Attrs.new(labels, &block).to_tables #=> {:name => {:header => ..}, :age => {:header => ..}
    end

    def table(&block)
      @tables << Table.new(&block)
    end

    def method_missing(method, *args, &block)
      @tables << Table.new(method)
    end
  end

  class Renderer
    def initialize(table)
      @table = table
    end

    def template
      @table.template_name
    end
  end

  class Attrs < AbstractTable
    attr_reader :attrs

    #include FooHelper

    def initialize(labels, &block)
      @attrs = {}
      @labels = labels
      self.instance_eval(&block) if block_given?
    end

    #def self.to_hash(*args, &block)
    #  self.new(*args, &block).attrs
    #end

    def method_missing(name, *args)
      inner = @labels.zip(args)
      @attrs[name.to_sym] = Hash[*inner.flatten]
    end

    def to_tables
      @attrs.map do |name, hash|
        Table.new(name) do
          default(hash)
        end
      end
    end
  end


  class Template
    attr_reader :members

    def initialize(labels)
      @members = {}
      @labels = labels
    end

    def self.build(*args, &block)
      self.new.instance_eval(*args, &block).members
    end

    def method_missing(name, *args)
      opt = args.extract_options!
      @members[name.to_sym] = {:elems => args, :option => opt}
    end
  end
end
