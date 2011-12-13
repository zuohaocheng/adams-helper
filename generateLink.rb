#!/usr/bin/env ruby
# ModelName = 't'
Version = 'generateLink, 2011-10-20, ZUO Haocheng'

SampleFile =<<EOF
#!ADAMSJOINTS, ModelName, iconSize=1
#THIS IS A SAMPLE
#Part1, Part2, Type, x, y, z, a, b, c, group
AXIS, BEARING, Revolute, 0.0, -1e-2, 1, 90, 0, 90, ab
AXIS, GEAR, Fixed, 0, 0, 0, 0, 0, 0
AXIS, Motor, motor_linear, 0, 0, 0, 0, 0, 0
AXIS, Motor, sensor, 0, 0, 0, 0, 0, 0
EOF

IconSizeDefault = 1 #5e-3

options = {}

########

def triNum tokens
  raise Errno::EINVAL, "Should be \"a, b, c\", #{tokens.join ', '}" if tokens.length != 3
  tokens.map {|s| s.to_f}
end

class Point
  attr_accessor :x, :y, :z
  def self.fromString str
    point = Point.new

    data = triNum str
    unless data.empty?
      point.x = data[0]
      point.y = data[1]
      point.z = data[2]
    else
      nil
    end
    point
  end
  
  def initialize x = 0.0, y = 0.0, z = 0.0
    @x = x
    @y = y
    @z = z
  end

  def inspect
    "Point {#{@x}, #{@y}, #{@z}}"
  end

  def to_s
    "#{@x}, #{@y}, #{@z}"
  end
end

class Vector
  attr_accessor :a, :b, :c

  def self.fromString str
    vec = Vector.new

    data = triNum str
    unless data.empty?
      vec.a = data[0]
      vec.b = data[1]
      vec.c = data[2]
    else
      nil
    end
    vec
  end

  def initialize a = 0.0, b = 0.0, c = 0.0
    @a = a
    @b = b
    @c = c
  end

  def inspect
    "Vector {#{@a}, #{@b}, #{@c}}"
  end

  def to_s
    "#{@a}, #{@b}, #{@c}"
  end
end

module UniqueName
  module UniqueNameClass
    def newName str
      return nil unless str
      @base_names ||={}

      count = @base_names[str]
      if count
        str_t = "#{str}_#{count}"
        count += 1
        @base_names[str] = count
      else
        str_t = str
        @base_names[str] = 2
      end
      str_t
    end
  end
    
  def self.included base
    base.extend UniqueNameClass
  end
end

class Marker
  include UniqueName
  
  attr_accessor :point, :vec, :name, :comments

  def initialize point = nil, vec = nil, name = nil, comments = nil
    @point = point
    @vec = vec
    @comments = comments

    @name = Marker.newName name
  end

  def inspect
    out = "{#{@point.inspect}, #{@vec.inspect}}"
    out = "#{@name}:" +out if name
    out
  end

  def to_s
    [@point, @vec].join ', '
  end

  def to_cmd # *option
    raise Errno::EINVAL, "Marker.name not specified for #{self}." unless @name
    # if option.member? :noDir
    #   orientation = ''
    # else
    #   orientation = "\n  orientation = #{@vec.to_s} &"
    # end
    
    <<EOF
marker create marker_name = #{@name} &
  comments = "#{@comments}" &
  orientation = #{@vec.to_s} &
  location = #{@point.to_s} 
entity attributes entity_name = #{@name} &
  name_visibility = off &
  size_of_icons = #{IconSize}
EOF
  end
end

######

class DOF
  attr_accessor :x, :y, :z, :a, :b, :c
  def initialize params = []
    from_a params
  end

  def from_a params = []
    @x, @y, @z, @a, @b, @c = params.member?(:x), params.member?(:y), params.member?(:z), params.member?(:a), params.member?(:b), params.member?(:c)
  end
  
  def to_a
    ret = []
    ret.push :x if @x
    ret.push :y if @y
    ret.push :z if @z
    ret.push :a if @a
    ret.push :b if @b
    ret.push :c if @c
    ret
  end

  def to_s
    a = self.to_a
    if a.empty?
      '/'
    else
      a.to_s.upcase
    end
  end

  def + (another_dof)
    DOF.new(self.to_a + another_dof.to_a)
  end

  def self.type_from_dir dir_sym
    if [:a, :b ,:c].member? dir_sym
      dir = {:a => :x, :b => :y, :c => :z}[dir_sym]
      {:type => :torque, :dir => dir}
    elsif [:x, :y ,:z].member? dir_sym
      {:type => :force, :dir => dir_sym}
    else
      raise Errno::EINVAL, "Invalid direction #{dir_sym}"
    end
  end
  
  def self.dir_func_cmd type, dir_sym, markers
    dir = dir_sym.to_s
    if type == :force
      lval = "#{dir}_force_function"
      d_fun = "D#{dir.upcase}"
      v_fun = "V#{dir.upcase}"
    elsif type == :torque
      lval = "#{dir}_torque_function"
      d_fun = "A#{dir.upcase}"
      v_fun = "W#{dir.upcase}"
    end

    d_val = "#{d_fun}(#{markers[0].name}, #{markers[1].name}"
    d_val += ", #{markers[1].name}" if type == :force
    d_val += ')'
    v_val = "#{v_fun}(#{markers[0].name}, #{markers[1].name}, #{markers[1].name})"
    
    {:d => d_val, :v => v_val}
  end

  def dir_cmd dir_sym, group, markers
    type_d = DOF.type_from_dir dir_sym
    type = type_d[:type]
    dir = type_d[:dir]

    if type == :force
      lval = "#{dir.to_s}_force_function"
    elsif type == :torque
      lval = "#{dir.to_s}_torque_function"
    end
    
    if group.dof.to_a.member? dir_sym
      if group.motor
        return <<EOF
#{lval} = "VARVAL(#{group.variable(dir_sym, :in).name})" &
EOF
      else
        d_var = group.variable(dir_sym, :k).name
        v_var = group.variable(dir_sym, :c).name

        val = DOF.dir_func_cmd type, dir, markers

        d_exp = " - #{d_var} * #{val[:d]}"
        v_exp = " - #{v_var} * #{val[:v]}"

      return <<EOF
#{lval} = "#{d_exp} #{v_exp}" &
EOF
      end
    else
      return <<EOF
#{lval} = "0.0" &
EOF
    end
  end

  def torque_cmd group, markers
    [:x, :y, :z, :a, :b, :c].map {|dir| self.dir_cmd dir, group, markers}.join "  "
  end
end

######

class Variable
  attr_accessor :name, :dir, :type, :surfix, :unit, :comment, :value

  def initialize dir, type, surfix, comment = '', value = nil
    @dir, @type, @surfix, @comment, @value = dir, type, surfix, comment, value

    type_t = true if [:a, :b, :c].member? dir

    @unit = if type_t
              'torsion_'
            else
              ''
            end
    @name = ".#{ModelName}."
    
    if type == :k
      @value ||= 1e4 
      @unit += 'stiffness'
      @name += 'K'
    elsif type == :c
      @value ||= 0.0
      @unit += 'damping'
      @name += 'C'
    else
      raise Errno::EINVAL, "Invalid type #{type} of Variable"
    end

    @name += 'T' if type_t
    @name += "#{dir.to_s}_#{surfix}"
  end

  def to_cmd
    <<EOF
variable create variable_name = #{@name} &
  real = #{@value} &
  units = #{@unit} &
  use_range = no &
  comments = "#{@comment}"
EOF
  end
end

class StateVar
  attr_accessor :name, :dir, :func, :initial_cond, :type, :comment
  def initialize dir, type, surfix, markers, initial_cond = 0.0, comment = '', options={}
    @initial_cond, @comment = initial_cond, comment
    if type == :in
      @name = ".#{ModelName}.In_#{dir.to_s}_#{surfix}"
      @func = '0.0'
    elsif [:d, :v].member? type
      @name = ".#{ModelName}.#{type.to_s.upcase}#{dir.to_s}_#{surfix}"
      @func = (DOF.dir_func_cmd :force, dir, markers)[type]
    else
      raise Err::EINVAL, "Invalid type #{type} of State Variable"
    end
  end

  def to_cmd
    <<EOF
data_element create variable variable_name = #{@name} &
  function = "#{@func}" &
  initial_condition = #{initial_cond} &
  comments = "#{@comment}"
EOF
  end
end

class Group
  include UniqueName
  attr_accessor :name, :dof, :motor

  @@groups = {}

  def self.newGroup str, options={}
    Group.new self.newName(str), options
  end

  def self.groupFromString str, options={}
    # if options[:motor]
    #   self.newGroup(str, options)
    # else
      @@groups[str] || self.newGroup(str, options)
    # end
  end

  def initialize name, options
    raise Errno::EAGAIN, "Another group named #{name} exists" if @@groups[name]
    @name = name
    @@groups[name] = self
    @dof = DOF.new [] #[:x, :y, :z, :a, :b, :c]
    @variables = {}
    if options[:motor]
      @motor = true
      @markers = options[:markers]
      raise Errno::EINVAL, "Group-motor must have markers." unless @markers
    end
  end

  def self.to_cmd
    @@groups.map {|k, v| v.to_cmd unless v.motor}.join "\n"
  end

  def add_dof dof
    @dof += dof
  end

  MotorVars = [:in, :d, :v]
  SpringVars = [:k, :c]
  
  def variable dir, type, comment = '', value = 0
#    p @dof.to_a unless @dof.to_a.member? dir
    raise Errno::EINVAL, "Invalid direction #{dir}" unless @dof.to_a.member? dir
    if SpringVars.member? type
      @variables[[dir,type]] ||= Variable.new(dir, type, @name)
    elsif MotorVars.member? type
      @variables[[dir, type]] ||= StateVar.new(dir, type, @name, @markers)
    else
      raise Errno::EINVAL, "Invalid variable type #{type}"
    end
  end
  
  def variables
    if @motor
      types = MotorVars
    else
      types = SpringVars
    end
    @dof.to_a.map { |dir| types.map{|type| self.variable(dir, type)}}.flatten
  end

  def to_cmd
    <<EOF
!---Build variables---
#{self.variables.map{|var| var.to_cmd}.join "\n"}

EOF
  end
end

# Group.groupFromString 'a'
# puts Group.to_cmd

######

class JointType
  include UniqueName
  attr_reader :name, :identifier, :dof, :prime, :none, :motor

  def self.initialize
    @@jointTypeDict = {}
    @@identifiers = {}

    JointType.new 'Spherical', /^S/i, DOF.new([:a, :b, :c])
    JointType.new 'Revolute', /^R/i, DOF.new([:a])
    JointType.new 'Cylindrical', /^C/i, DOF.new([:x, :a])
    JointType.new 'Translational', /^T/i, DOF.new([:x])
    JointType.new 'Fixed', /^F/i, DOF.new([])
    
    JointType.new 'Inplane', /^IP$/i, DOF.new([:x, :y, :a, :b, :c]), :prime

    JointType.new 'none', /^none$/i, DOF.new([:x, :y, :z, :a, :b, :c]), :none
    JointType.new 'none_translational', /^none_t/i, DOF.new([:x]), :none

    JointType.new 'motor_linear', /^motor_[lt]/i, DOF.new([:x]), :motor
    JointType.new 'sensor', /^sensor/i, DOF.new([:x, :y, :z, :a, :b, :c]), :sensor
  end

  def self.to_s
    "Name\tIdentifier\tDOF\tisJoint\n" + @@jointTypeDict.sort.map { |obj| obj[1].to_s}.join
  end

  def to_s
    <<EOF
#{@name}\t#{@identifier.inspect}\t#{@dof}\t#{@none}
EOF
  end

  def none?
    @none
  end
  
  def self.typeFromString str
    name = (@@identifiers.find {|k,v| str.match k} || [])[1]
    @@jointTypeDict[name] || raise(Errno::EINVAL, "Invalid type of joint #{str}")
  end

  def initialize name, identifier, dof, *options
    @name, @identifier, @dof = name, identifier, dof
    @prime = options.member? :prime
    @none = options.member? :none
    if options.member? :motor
      @motor = true
      @none = true
    elsif options.member? :sensor
      @sensor = true
      @motor = true
      @none = true
    end
    
    @@jointTypeDict[name] = self
    @@identifiers[identifier] = name
  end

  def to_cmd jointName, markers
    return '' if @none
    
    if @prime
      header = <<EOF
constraint create primitive_joint #{@name} &
  jprim_name = #{jointName} &
EOF
    else
      header = <<EOF
constraint create joint #{@name} &
  joint_name = #{jointName} &
EOF
    end
    header.chop!

    <<EOF
#{header}
  i_marker_name = #{markers[0].name} &
  j_marker_name = #{markers[1].name}
entity attributes entity_name = #{jointName} &
  name_visibility = off &
  size_of_icons = #{IconSize}
EOF

  end

  def to_cmd_torque torqueName, group, markers, comment = ''
    return group.to_cmd if @sensor && group.motor
    torqueName = JointType.newName torqueName

    <<EOF
#{group.to_cmd if group.motor}
force create direct general_force &
  general_force_name = #{torqueName} &
  i_marker_name = #{markers[0].name} &
  j_part_name = (eval(#{markers[1].name}.parent)) &
  ref_marker_name = #{markers[1].name} &
  #{self.dof.torque_cmd(group, markers).chop}
  comments = "#{comment}"
entity attributes entity_name = #{torqueName} &
  name_visibility = off &
  size_of_icons = #{IconSize}
EOF

  end

  self.initialize
end

######
  
class Entry
  attr_accessor :parts, :type, :marker, :group, :line

  def initialize parts, type, marker, line, group = nil
    @parts, @marker, @line = parts, marker, line

    @type = JointType.typeFromString type

    @group =  if group == nil || group.empty?
                Group.newGroup "#{parts[0]}_#{parts[1]}", {:motor => @type.motor, :markers => self.torqueMarkers}
              else
                Group.groupFromString group, {:motor => @type.motor, :markers => self.torqueMarkers}
              end
    @group.add_dof @type.dof

  end
  
  def inspect
    "{#{@parts}, #{@type}, #{@marker}, #{group}}"
  end
  
  def valid?
    true
  end

  def to_csv
    [@parts, @type.name, @marker.to_s, @group.name].flatten.join ', '
  end

  def to_cmd
    raise Errno::ENOSYS, "Invalid parts.length for #{@self}." unless @parts.length == 2

    self.joint #+ self.torque
  end

  def joint
    <<EOF
!---Build joint between #{@parts[0]} and #{@parts[1]}, line #{@line} ---
#{self.jointMarkersCmd}
#{self.jointConstraint}

!---Build torque between #{@parts[0]} and #{@parts[1]}, line #{@line}---
#{self.torqueMarkersCmd}
#{self.torque}
EOF
  end

  def marker parts, type
    name = ".#{ModelName}.#{parts[0]}.m#{type}_#{parts[1]}"
    markerComment = if type == 'j'
                      'Marker for constraint'
                    elsif type == 't'
                      'Marker for torque'
                    elsif
                      raise Errno::EINVAL, "Invalid type #{type} for marker"
                    end
    comment = "#{markerComment} to #{parts[1]} on #{parts[0]}"
    marker = Marker.new @marker.point, @marker.vec, name, comment
  end

  def jointMarkers
    @jointMarkers = [self.marker(@parts, 'j'), self.marker(@parts.reverse, 'j')] unless @jointMarkers 
    @jointMarkers
  end

  def jointMarkersCmd
    self.jointMarkers.map {|marker| marker.to_cmd}.join "\n" unless @type.none?
  end

  def torqueMarkers
    @torqueMarkers = [self.marker(@parts, 't'), self.marker(@parts.reverse, 't')] unless @torqueMarkers
    @torqueMarkers
  end
  
  def torqueMarkersCmd
    self.torqueMarkers.map {|marker| marker.to_cmd}.join "\n" unless @type.dof.to_a.empty?
  end

  def jointConstraint
    jointName = ".#{ModelName}.#{@parts[0]}_#{@parts[1]}"
    @type.to_cmd jointName, self.jointMarkers
  end
  
  def torque
    @type.to_cmd_torque ".#{ModelName}.F_#{@parts[0]}_#{@parts[1]}" , @group, @torqueMarkers, "Torque between #{@parts[0]} and #{@parts[1]}" unless @type.dof.to_a.empty?
  end
end

########

require "#{File.dirname(__FILE__)}/adams"

usage = 'Usage: generateLink.rb [inputfile] [options]'
adams = ZHAdams.new :sample => SampleFile, :version => Version, :usage => usage do |opts|
  opts.on_tail("-l", "--link", "Show available links") do
    $stderr.puts JointType.to_s
    exit
  end

  opts.on("-k", "--check", "Check and output evaluated file") do
    options[:check] = true
  end
end

header = lambda do |tokens, out|
  ModelName = tokens[1]
  IconSize = if tokens[2] && !tokens[2].strip.empty?
               tokens[2].to_f
             else
               IconSizeDefault
             end
end

entries = []
content = lambda do |tokens, ln, b|
    marker = Marker.new(Point.fromString(tokens[3..5]), Vector.fromString(tokens[6..8]))
    
    parts = [tokens[0]]
    parts.push tokens[1] unless tokens[1].empty?

    entries.push Entry.new parts, tokens[2], marker, ln, tokens[9]  
end

adams.parse('#!ADAMSJOINTS', content, header)

outFd = adams.out

if options[:check]
  outFd.puts "#!ADAMSJOINTS, #{ModelName}, #{IconSize}"
  outFd.puts entries.map {|entry| entry.to_csv}.join "\n"
else
  outFd.puts "!Generated by generateLink, 2011 ZUO Haocheng"
  outFd.puts "undo begin"

  outFd.puts Group.to_cmd
  outFd.puts entries.map {|entry| entry.to_cmd}.join ''

  outFd.puts "undo end"
  outFd.puts "!Script ends here. 2011 ZUO Haocheng"
end
