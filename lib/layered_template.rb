# -*- encoding: utf-8 -*-

$:.unshift File.dirname(__FILE__)

require File.dirname(__FILE__) + "/layered_template/config"
require File.dirname(__FILE__) + "/layered_template/helper"

require 'rubygems'
require "active_support"
require 'active_support/core_ext/array'
require 'erb'
require "getoptlong"

BASE_DIR = File.dirname(__FILE__) + "/.."

class LayeredTemplate
  def initialize(src=nil, &block)
    c = LayeredTemplateForRunningDSL.new(self)
    block_given? ?  c.instance_eval(&block) : c.instance_eval(src)
    @tables = c.tables
  end

  def self.load(tpl_fname)
    self.new(File.read(tpl_fname))
  end

  def output(dir=nil)
    @tables.map{|dc| dc.output(dir)}.join
  end

  def find_table(name)
    @tables.find{|t| t.name.to_sym == name.to_sym} or raise "The table is not found. '#{@tables.map(&:name).inspect}' do not have '#{name}' "
  end

#  def inspect
#    <<EOS
##<LayeredTemplate:0x1016b67f8
#  @tables=[
#    #{@tables.map(&:inspect).join("\n")}
#  ]
#>
#EOS
#  end
end

class LayeredTemplateForRunningDSL
  attr_reader :tables

  def initialize(parent)
    @parent = parent
    @tables = []
  end

  def table(name, &block)
    @tables ||= []
    @tables << Table.new(@parent, name, &block)
  end
end

class Table
  attr_reader :name, :d_attr_block, :d_attrs

  def initialize(parent, name, &block)
    @parent = parent
    @name = name
    (c = TableForRunningDSL.new(self)).instance_eval(&block)
    @templates = c.templates
    @tpl_opt = c.tpl_opt
    @d_attrs = c.d_attrs
    @tables = c.tables
  end

  def d_item(name)
    item = self.d_attrs.find{|name_, _, _| name_ == name.to_sym} || []
    [item[1], item[2]]
  end

  def output(dir=nil)
    @templates.map{|t| t.output(dir)}.join
  end

  def find_table(name)
    @tables.find{|t| t.name.to_sym == name.to_sym} or @parent.find_table(name)
  end

#  def inspect
#<<EOS
##<Table:
#  @templates:
#    elems
#    #{@tamplates.map(&:inspect).join("\n")}
#  attrs:
#    #{}
#  @tables:
#    #{}
#EOS
#  end
end

class TableForRunningDSL
  attr_reader :templates, :tpl_opt, :d_attrs, :tables

  def initialize(parent)
    raise ArgumentError unless parent.kind_of?(Table)
    @parent = parent
    @templates = []
    @tpl_opt = {}
    @d_attrs = []
    @tables = []
  end

  def template(template_name, &block)
    @templates << Template.new(@parent, template_name, @tpl_opt, &block)
    @tpl_opt = {}
  end
  alias_method :deploy, :template

  def location(fname, location_id=nil)
    @tpl_opt[:fname] = fname
    @tpl_opt[:loc_id] = location_id
  end

  def enum(enum_in, enum_out)
    @tpl_opt[:enum_in] = enum_in
    @tpl_opt[:enum_out] = enum_out
  end

  def attrs(labels, &block)
    @d_attr_block = DbAttrBlock.new(labels, &block)
    @d_attrs = @d_attr_block.elems
  end

  def table(name, &block)
    @tables ||= []
    @tables << Table.new(@parent, name, &block)
  end

end

class Template
  attr_reader :table, :t_attrs

  def initialize(table, template_name, opt={}, &block)
    raise ArgumentError unless table.kind_of?(Table)
    @table = table
    @elems = []
    @opt = {}
    @template_fname = Helper.find_template("#{template_name}.#{self.ext}") or raise "The template file '#{template_name}.#{self.ext}' does not found."
    (t = TemplateForRunningDSL.new).instance_eval(&block)
    @t_attrs = t.elems
  end

  def output(dir=nil)
    sandbox = Sandbox.new(self)
    erb = ERB.new(File.read(@template_fname), nil, '-')
    erb.filename = @template_fname
    erb_result = erb.result(sandbox.instance_eval("binding"))
    if @opt[:fname] && dir
      OutputManager.push("#{dir}/#{fname}", @opt[:loc_id], erb_result)
      nil
    else
      erb_result
    end
  end

  def t_item(name)
    item = self.t_attrs.find{|name_, _, _| name_ == name.to_sym} || []
    [item[1], item[2]]
  end

  def ext
    "html.haml" # TODO: 後で修正
  end
end

class TemplateForRunningDSL
  attr_reader :elems

  def initialize
    @elems = []
  end

  def method_missing(name, *args)
    opts = args.extract_options!
    @elems << [name.to_sym, args.map{|a| Value.new(a)}, opts]
  end
end

class Sandbox
  def initialize(template, opt={})
    @template = template
    @enum = (opt[:enum_in] && opt[:enum_out])
    @enum_in = opt[:enum_in] || "objs"
    @enum_out = opt[:enum_out] || "obj"

    self.class.class_eval do
      # Names defined in template block can be called in erb.
      template.t_attrs.each do |name, args, opts|
        unless respond_to?(name)
          define_method name do
            template.t_item(name).first.map{|item| render(item)}.join("\n")
          end
        end
      end
    end
  end

  def t_attrs
    @template.t_attrs
  end

  # itemの型に応じてテキストに変換する
  def render(items, opts={})
    [items].flatten.map do |item|
      case item.type
      when :table_or_attr
        attr_, opts = @template.table.d_item(item.v)
        if attr_
          filter(opts[:val] || "")
        else
          tbl(item.v)
        end
      when :source
        filter item.v
      else
        raise ArgumentError, "#{item.inspect} must be :table_or_attr or :source"
      end
    end.join("\n")
  end

  # nameという名前のテーブルを描画する
  def tbl(name)
    @template.table.find_table(name).output
  end

  # 頭文字r>などによって加工する
  def filter(str)
    case str
    when /\Ar>\s*(.*?)\Z/
      $1
    else
      str
    end
  end

  # enum定義がされているときのみ
  # ループを回す
  def enum_wrap(&block)
    # TODO: 以下はどうなる?
    # * 「enum_wrapで囲まれた要素の前後にstrを挿入」ができない
    block.call
  end
end

class DbAttrBlock
  attr_accessor :elems

  def initialize(labels, &block)
    @labels = labels
    (c = DbAttrBlockForRunningDSL.new(labels)).instance_eval(&block)
    @elems = c.elems
  end
end

class DbAttrBlockForRunningDSL
  attr_reader :elems

  def initialize(labels)
    @labels = labels
    @elems = []
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

