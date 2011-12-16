require 'optparse'

# for safety of eval
def extern_block
  binding
end
Eb = extern_block

class String
  def emphasize
    redColor="[31;1m"
    blackColor="[0m"
    redColor + self + blackColor
  end

  def to_f
    eval(self, Eb).to_f
  end
end

class ZHAdams
  attr_accessor :model
  attr_accessor :in, :out
  attr_accessor :file, :ln

  def set_opt options, ioptions={}
    OptionParser.new do |opts|
      opts.banner = ioptions[:usage] if ioptions.member? :usage

      opts.on("-o", "--output FILENAME", "Set output file") do |f|
        options[:output] = f
      end

      opts.on("-i", "--stdin", "Allow input from tty-stdin") do
        options[:stdin] = true
      end

      opts.on("-D", "--define COMMAND", "Execute command") do |c|
        eval(c, Eb)
      end
      
      opts.on_tail("-c", "--coordinate", "Show coordinates in euler angles") do
        puts <<EOF
Euler angles, 313
X\t0,0,0
Y\t90,180,0
Z\t90,90,90
EOF
        exit
      end

      if ioptions.member? :sample
        opts.on_tail("-s", "--sample", "Show sample input") do
          $stdout.puts ioptions[:sample]
          exit
        end
      end

      if ioptions.member? :version
        opts.on_tail("--version", "Show version") do
          $stderr.puts ioptions[:version]
          exit
        end
      end
    end
  end

  def stdin inputFiles, isStdin
    if isStdin || inputFiles.empty?
      inputFd = $stdin
      @file = 'stdin'
    else
      @file = inputFiles[0]
      begin
        inputFd = File.open @file
      rescue
        $stderr.puts "Can't open file #{inputFile}, #{$!}"
        exit
      end
    end
    inputFd
  end

  def stdout outFile
    if outFile
      begin
        outFd = File.open outFile, 'w'
      rescue
        $stderr.puts "Can't write file #{inputFile}, #{$!}"
        exit
      end
    else
      outFd = $stdout
    end
    outFd
  end
  
  def stdio inputFiles, options
    @in, @out = self.stdin(inputFiles, options[:stdin]), self.stdout(options[:output])
  end

  def gen_tokens line
    line.chomp.split(',').map{|token| token.strip}
  end
  
  def parseHeader line, headerId, block
    tokens = gen_tokens line
    if tokens[0] != headerId
      raise Errno::EINVAL, "Input file format err."
    elsif tokens[1] == nil || tokens[1].empty?
      raise Errno::EINVAL, "No model name specified" 
    end

    @model = tokens[1]
    
    block.call tokens, @out if block
  end

  def parse headerId, lineBlock = nil, headerBlock = nil, &lineBlockA
    header = @in.gets
    self.parseHeader header, headerId, headerBlock

    @ln = 1
    while (line = @in.gets)
      self.ln += 1 if @line_inc
      lineBlock ||= lineBlockA
      self.parseContentLine line, lineBlock
    end
  end

  def parseContentLine line, block
    line.strip!
    case line[0..0]
    when '!'
      eval(line[1..-1], Eb)
    when '#'
    else
      tokens = gen_tokens line
      return if !tokens || tokens.empty?

      case tokens[0][0..0]
      when '%'
        self.ln = tokens[0][1..-1].to_i
        @file = tokens[1]
        @line_inc = false
      else
        begin
          block.call tokens, @ln, @out
        rescue
          addr = "#{@file}:#{@ln}"
          # @errors[addr] ||= 0
          # @errors[addr] += 1

          # if @errors[addr] == 1
          $stderr.print addr.emphasize + ': '
          $stderr.puts $!
          $stderr.print line
          # end
        end
      end
    end
  end
  
  def initialize ioptions={}
    options = {}
    opts = self.set_opt options, ioptions
    yield opts
    begin
      opts.parse!

      if ARGV.empty? && !options[:stdin] && $stdin.isatty
        raise Errno::EINVAL, "error: no input files"
      end
    rescue
      $stderr.puts "#{$!}"
      $stderr.puts opts
      exit
    end

#    inputFiles = ARGV
    self.stdio ARGV, options

    @line_inc = true
    # @errors = {}
  end
end
