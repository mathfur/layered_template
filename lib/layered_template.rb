# -*- encoding: utf-8 -*-

$:.unshift File.dirname(__FILE__)

require File.dirname(__FILE__) + "/layered_template/config"
require File.dirname(__FILE__) + "/layered_template/helper"

require 'rubygems'
require "active_support"
require 'active_support/core_ext/array'
require 'erb'
require "getoptlong"
require "fileutils"

BASE_DIR = File.dirname(__FILE__) + "/.."

module LayeredTemplate
  class Main
    attr_reader :config

    def initialize(src=nil, &block)
      c = LayeredTemplateForRunningDSL.new(self)
      block_given? ?  c.instance_eval(&block) : c.instance_eval(src)
      @tables = c.tables
      @config = c.config_
    end

    def self.load(tpl_fname)
      self.new(File.read(tpl_fname))
    end

    def output
      @tables.map{|dc| dc.output}.join
    end

    def find_table(name)
      @tables.find{|t| t.name.to_sym == name.to_sym} or (STDERR.puts "The table is not found. '#{@tables.map(&:name).inspect}' do not have '#{name}' "; nil)
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
end

class LayeredTemplateForRunningDSL
  attr_reader :tables, :config_

  def initialize(parent)
    @parent = parent
    @tables = []
    @config_ = {}
  end

  def table(name, &block)
    @tables ||= []
    @tables << Table.new(@parent, name, &block)
  end

  def config(&block)
    (c = ConfigForRunningDSL.new).instance_eval(&block)
    @config_.merge(c.config)
  end
end

class Table
  attr_reader :name, :d_attr_block, :d_attrs, :config

  def initialize(parent, name, &block)
    @parent = parent
    @name = name
    (c = TableForRunningDSL.new(self)).instance_eval(&block)
    @templates = c.templates
    @tpl_opt = c.tpl_opt
    @d_attrs = c.d_attrs
    @tables = c.tables
    @config = @parent.config
  end

  def d_item(name)
    item = self.d_attrs.find{|name_, _, _| name_ == name.to_sym} || []
    [item[1], item[2]]
  end

  def output
    @templates.map{|t| t.output}.join
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
  attr_reader :table, :t_attrs, :config

  def initialize(table, template_name, opt={}, &block)
    raise ArgumentError unless table.kind_of?(Table)
    @table = table
    @elems = []
    @opt = opt
    @template_fnames = LayeredTemplate::Helper.find_templates(template_name)
    raise "The template file '#{template_name}' does not found." if @template_fnames.blank?
    (t = TemplateForRunningDSL.new).instance_eval(&block)
    @t_attrs = t.elems
    @config = @table.config
  end

  def output
    return_val = ''
    sandbox = Sandbox.new(self)
    @template_fnames.each do |template_fname|
      erb = ERB.new(File.read(template_fname), nil, '-')
      erb.filename = template_fname
      erb_result = erb.result(sandbox.instance_eval("binding"))
      if @opt[:fname] || sandbox.fname
        OutputManager.push(@opt[:fname] || sandbox.fname, @opt[:loc_id] || sandbox.loc_id, erb_result)
      else
        return_val += erb_result
      end
    end
    return_val
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
  attr_reader :fname, :loc_id

  def initialize(template, opt={})
    @template = template

    #self.class.class_eval do
    #  # Names defined in template block can be called in erb.
    #  template.t_attrs.each do |name, args, opts|
    #    unless respond_to?(name)
    #      define_method name do
    #        template.t_item(name).first.map{|item| render(item)}.join("\n")
    #      end
    #    end
    #  end
    #end
  end

  private
  def t_attrs(name_ = nil)
    result = @template.t_attrs.select do |name, items, opts|
      !name_ || name_.to_sym == name.to_sym
    end.map do |name, items, opts|
      attr_opt_sum = {}
      items.select{|item| item.type == :table_or_attr}.each do |item|
        _, opts_ = @template.table.d_item(item.v)
        attr_opt_sum = attr_opt_sum.merge(opts_ || {})
        item.instance_eval do
          (opts_ || {}).reject{|k, v| k.to_s.include?('-') }.each do |k, v|
            eval(<<EOS)
def #{k.to_s}
  #{opts_[k.to_s.to_sym].inspect}
end
EOS
          end
          eval(<<EOS)
def [](k)
  opts_[k.to_s.to_sym].inspect
end
EOS
        end
        eval(<<EOS)
def item.[](k)
  opts_[k.to_sym]
end
EOS
      end
      opts = attr_opt_sum.merge(opts)
      [name, items, opts]
    end

    if name_
      result.map{|_, items, opts| [items, opts]}
    else
      result
    end
  end

  def r(item); h(render(item)); end
  def r2(item); h2(render(item)); end
  def r4(item); h4(render(item)); end
  def r6(item); h6(render(item)); end
  def r8(item); h8(render(item)); end

  # itemの型に応じてテキストに変換する
  def render(items, opts={})
    result = [items].flatten.map do |item|
      item = Value.new(item) unless item.kind_of?(Value)
      case item.type
      when :table_or_attr
        attr_, opts = @template.table.d_item(item.v)
        if attr_
          # item in d_attrs
          opts[:val] || ""
        elsif (as = t_attrs(item.v)).present?
          # bodyとかt_attrsで定義されている場合
          as.map{|items_, _| render(items_)}.join("\n")
        else
          # item in t_attrs
          tbl(item.v)
        end
      when :source
        item.v
      else
        raise ArgumentError, "#{item.inspect} must be :table_or_attr or :source"
      end
    end.join("\n")

    result.present? && result
  end

  def r!(items, opts={})
    render(items, opts) or raise "Fail to render #{items.inspect}"
  end

  # nameという名前のテーブルを描画する
  # If there is not the table, then return nil.
  def tbl(name)
    @template.table.find_table(name).try(:output)
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

  def table_name
    @template.table.name
  end

  # example:
  # 'abc' => :abc
  # "ab'c" => :'ab\'c'
  def to_symbol(str)
    case str
    when /'/
      ":'" + str.to_s.gsub("'"){ "\\'" } + "'"
    else
      ':' + str.to_s
    end
  end

  # example:
  #  "abc" => '\'abc\''
  #  "ab'c" => '\'abc\''
  def to_quote(str)
    case str
    when /'/
      "'" + str.to_s.gsub("'"){ "\\'" } + "'"
    else
      "'" + str.to_s + "'"
    end
  end

  def output_to(fname, loc_id=nil)
    @fname = fname
    @loc_id = loc_id || :main
  end

  def config(name)
    @template.config[name]
  end

  def enum
    @template.t_item(:enum).try(:first)
  end

  def enum_in
    enum.try(:first)
  end

  def enum_out
    enum.try(:last)
  end

  # name -> Hash
  def opts(name)
    @template.t_item(name).last
  end

  # === helpers =================
  def i2(str); i_n(str, 2); end
  def i4(str); i_n(str, 4); end
  def i6(str); i_n(str, 6); end
  def i8(str); i_n(str, 8); end

  def i_n(str, n)
    str.to_s.split(/\n/).map{|line| " "*n + line }.join("\n").lstrip
  end

  def h(str); haml_element(str, 2); end
  def h2(str); haml_element(str, 2); end
  def h4(str); haml_element(str, 4); end
  def h6(str); haml_element(str, 6); end
  def h8(str); haml_element(str, 8); end

  # If %div have 4 indent,  then use like
  # %div<%= haml_element(body, 4) %>
  def haml_element(str, indent_size=2)
    raise ArgumentError, "#{str.inspect} is not String." unless str.kind_of?(String)
    lines = str.split(/\n/)
    case str
    when /\Ar>\s*(.*?)\Z/
      "= #$1"
    when /^[-%]/
      "\n" + lines.map{|line| " "*(indent_size+2) + line.to_s}.join("\n")
    else
      " #{str}"
    end
  end

  def join_eq(hash)
    raise ArgumentError, "#{hash.inspect} should be Hash" unless hash.kind_of?(Hash)
    hash.map{|k, v| "#{k}='#{v}'"}.join(' ')
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
    raise ArgumentError, "@labels is wrong. @labels: #{@labels.inspect}" unless @labels.kind_of?(Enumerable) and @labels.all?{|label| label.respond_to?(:to_sym)}
    opts = args.extract_options!
    @elems << [name, args, Hash[*(@labels.map(&:to_sym).zip(args)).flatten].merge(opts)]
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
    @@contents[fname] ||= {}
    @@contents[fname][loc_id] ||= []
    @@contents[fname][loc_id] << content
  end

  def self.write_to_file(dir)
    @@contents.each do |fname, hash|
      output_path = "#{dir}/#{fname}"
      FileUtils.mkdir_p(File.dirname(output_path))
      open(output_path, 'w') do |f|
        output_str = hash.map do |_, contents|
          contents.join("\n")
        end.join("\n\n")
        puts "\n=== output_to:#{output_path}\n#{output_str}"
        if File.exist?(output_path)
          #STDERR.puts "現状では既存のファイルがある場合は上書きしない. fname: #{output_path}"
          #next
        end
        f.write output_str
        puts ">> write to #{output_path}"
      end
    end
  end
end

