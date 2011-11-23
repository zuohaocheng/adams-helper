#!/usr/bin/env ruby
require 'adams'

Version = 'generateMatrix, 2011-11-11, ZUO Haocheng'

SampleFile =<<EOF
#!ADAMSJMATRIX, ModelName, IconSize=1
#THIS IS A SAMPLE
#Part1, Part2, Type, Plane, density-u, density-v, x1, y1, z1, x2, y2, z2, a, b, c, group
AXIS, BEARING, none_translational, yz, 2, 1, 0, 1, 2, 0.0, -1e-2, 1, 90, 0, 90, ab
AXIS, GEAR, none, xy, 5, 3, 0, 0, 0, 1, 2, 0, 0, 0, 0

#Line start with @ will be output as is, without @
@AXIS, BEARING, Revolute, 0.0, -1e-2, 1, 90, 0, 90, ab
@AXIS, GEAR, Fixed, 0, 0, 0, 0, 0, 0
EOF

class FloatRange
  attr_accessor :min, :max, :count
  def initialize min, max, count = 10
    min, max = max, min if min > max
    raise Errno::EINVAL, "Count must be positive." if count <= 0
    @min, @max, @count = min, max, count
  end

  def each
    if @count == 1
      num = (@max + @min) / 2
      yield num
    else
      range = @max - @min
      step = range / (@count - 1)
      (0...@count).each do |i|
        num = @min + i * step
        yield num
      end
    end
  end
end

options = {:line => true}

adams = ZHAdams.new :sample => SampleFile, :version => Version, :usage => 'Usage: generateMatrix.rb [inputfile] [options]' do |opts|
  opts.on('-P', '--no-line' "Don't generate lines") do
    options[:line] = false
  end
end

headerPf = ''
header = lambda do |tokens, out|
  headerPf = tokens[2..-1].join ','
  out.puts "#!ADAMSJOINTS, #{adams.model}, #{headerPf}"
end

content = lambda do |tokens, ln, out|
  out.puts "% #{ln}, #{adams.file}" if options[:line]
  
#  $stderr.puts tokens.inspect
  if tokens[0][0] == '@'[0]
    tokens[0] = tokens[0][1..-1]
    out.puts tokens.join(', ')
    return
  end
  
  parts = tokens[0..1]
  type = tokens[2]
  plane = (%w{X Y Z} - tokens[3].upcase.unpack('aa').sort)
  density = tokens[4..5].map {|s| s.to_f.round}
  p1 = tokens[6..8].map {|s| s.to_f}
  p2 = tokens[9..11].map {|s| s.to_f}
  orientation = tokens[12..14]
  group = tokens[15]

  raise Errno::EINVAL, "Invalid plane #{tokens[3]}" if plane.length != 1 || !%w{X Y Z}.member?(plane_dir = plane[0])
  plane_dir_num = {:X => 0, :Y => 1, :Z => 2}[plane_dir.to_sym]
  pdn = plane_dir_num
  un = pdn +1
  vn = pdn +2
  un -= 3 if un >= 3
  vn -= 3 if vn >= 3
  
  raise Errno::EINVAL, "#{plane_dir}1 not equals to #{plane_dir}2." if p1[pdn]!= p2[pdn]

  outp = []
  outp[pdn] = p1[pdn]

  FloatRange.new(p1[un], p2[un], density[0]).each do |u|
    FloatRange.new(p1[vn], p2[vn], density[1]).each do |v|
      outp[un] = u
      outp[vn] = v
      out.puts [parts, type, outp, orientation, group].flatten.join ', '
    end
  end
end



adams.parse('#!ADAMSJMATRIX', content, header)

