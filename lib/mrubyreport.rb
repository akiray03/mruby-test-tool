#!/usr/bin/env ruby
# --*-- encoding: utf-8 --*--

require 'rubygems'
require 'logger'
require 'fileutils'
require 'yaml'
require 'uri'
require 'erb'
require 'time'
require 'cgi'

if $logger.nil?
  $logger = Logger.new(STDOUT)
  $logger.level = Logger::DEBUG
end

LOG_MAX = 100
DIR = File.dirname(__FILE__)

class Integer
  def to_c
    str = to_s
    tmp = ""
    while(str =~ /([-+]?.*\d)(\d\d\d)/) do
      str = $1
      tmp = ",#{$2}" + tmp
    end
    str + tmp
  end
end

class MrubyReport
  def initialize(filepath)
    @data = YAML.load(File.open(filepath))
    @data[:make_test] = mrbtest_result_parser(@data[:make_test])
    if @data[:posix_test]
      @data[:posix_test] = posixtest_result_parser(@data[:posix_test])
    end

    @repository = @data[:repository]
    @commit     = @data[:commit]
  end

  def git_url
    URI::Generic.build({
      :scheme => 'http',
      :host => 'github.com',
      :path => "/#{@repository}.git",
    }).to_s
  end

  #
  # mrbtestの結果をパースする
  #
  def mrbtest_result_parser(data)
    mrbtest = []
    flag = false
    test = testreport_default_value

    data[:stdout].split("\n").each do |line|
      case line
      when /^Total\:\s/
        test[:total] += line.split(":").last.to_i
      when /^\s+OK\:\s/
        test[:ok] += line.split(":").last.to_i
      when /^\s+KO\:\s/
        test[:ko] += line.split(":").last.to_i
      when /^Crash\:\s/
        test[:crash] += line.split(":").last.to_i
      when /^\sTime\:\s/
        test[:time] << line.split(":").last.strip
      when /^Fail\:\s/
        test[:fail] << line
      else
        # skip
      end
    end

    data.merge(test)
  end


  #
  # posix test の結果をパースする
  #
  def posixtest_result_parser(result)
    result.merge(msg_parser(result[:stdout].split("\n")))
  end

  def testreport_default_value
    {
      :total => 0,
      :ok    => 0,
      :ko    => 0,
      :crash => 0,
      :time  => [],
      :fail  => [],
      :msg   => [],
      :dots  => "",
    }
  end

  def msg_parser(msg)
    test = testreport_default_value
    flag = false

    if msg.nil?
      test[:total] = 1
      test[:crash] = 1
      test[:time] = '0.0 seconds'
      test[:fail] << "failed."
      return test
    end

    msg.each do |line|
      if flag
        test[:dots] += line
        flag = false
      else
        case line
        when /^\#\sexec\s/
          flag = true
        when /^\.\.\/bin\/mruby/
          flag = true
        when /^Total\:\s/
          test[:total] += line.split(":").last.to_i
        when /^\s+OK\:\s/
          test[:ok] += line.split(":").last.to_i
        when /^\s+KO\:\s/
          test[:ko] += line.split(":").last.to_i
        when /^Crash\:\s/
          test[:crash] += line.split(":").last.to_i
        when /^\sTime\:\s/
          test[:time] << line.split(":").last.strip
        when /^Fail\:\s/
          test[:fail] << line
        when /^\#+$/
          # skip
        else
          test[:msg] << line if line.size > 0
        end
      end
    end

    # time calc
    t = 0
    test[:time].each do |time|
      t += time.split(" ").first.to_f
    end
    test[:time] = "%.5f seconds" % t

    test
  end


  def success?
    ary = []
    ary << @data[:make][:status]
    ary << @data[:make_test][:status]
    if @data[:posix_test]
      ary << @data[:posix_test][:status]
    end
    ary.all? {|i| i == 'success' }
  end

  [:repository, :commit, :ball_id, :hostname, :make, :make_test, :posix_test, :env].each do |sym|
    eval "def #{sym}; @data[:#{sym}]; end"
  end

  def test
    @data[:make_test]
  end

  def posix
    @data[:posix_test]
  end

  def date
    @data[:date]
  end

  def filesize
    @data[:filesize]
  end

  def filesize_mruby
    if @data[:filesize] && @data[:filesize]['bin/mruby']
      @data[:filesize]['bin/mruby'].to_i.to_c
    end
  end

  def status
    success? ? 'success' : 'failed'
  end


  def inspect
    data = {
      :id => ball_id,
      :hostname => hostname,
      :status => status,
      :date => date,
    }

    "#<#{self.class}: #{data.inspect}>"
  end
end

class MrubyReportGenerator
  TMPDIR = File.expand_path('../../tmp', __FILE__)
  RESULT_DIR = File.expand_path('../../result', __FILE__)
  REPORT_DIR = File.expand_path('../../report', __FILE__)

  def initialize(opts = {})
    @opts = ({
      :git => 'git',
      :repositories => {},
    }).merge((opts or {}))
    @files = Dir.glob("#{RESULT_DIR}/*.yml").select{|fname| not fname.include?('akiray03') }

    if not File.exist? REPORT_DIR
      FileUtils.mkdir_p REPORT_DIR
    end

    @buildreport_template = File.join(DIR, "..", "template", "buildreport.html.erb")
    @repository_template = File.join(DIR, "..", "template", "repository.html.erb")
    @index_template = File.join(DIR, "..", "template", "index.html.erb")
    @frame_menu_template = File.join(DIR, "..", "template", "frame_menu.html.erb")
  end

  def load_files
    @reports = {}
    @files.each do |filepath|
      report = MrubyReport.new(filepath)
      id = report.ball_id
      @reports[id] = {}  if not @reports[id]
      @reports[id][report.hostname] = report
    end
  end

  def analyze_git
    repos = @reports.keys.map do |id|
      a, b, c = id.split('-')
      ["http://github.com/#{a}/#{b}.git", "#{a}-#{b}"]
    end.uniq

    @gitlog = {}
    @commitlog = {}

    @workdir = mktmpdir
    Dir.chdir(@workdir) do
      repos.each do |val|
        url, reponame = val
        `git clone #{url} #{reponame}`
        gitlog = []
        Dir.chdir(reponame) do
          `git log --oneline -n #{LOG_MAX}`.split("\n").each do |line|
            gitlog << line.split("\s", 2)
          end
          gitlog.each do |val|
            comm, msg = val
            @commitlog["#{reponame}-#{comm}"] = `git show #{comm}`
          end
        end
        @gitlog[reponame] = {:url => url, :gitlog => gitlog}

        if @opts[:repositories][reponame]
          branches = @opts[:repositories][reponame]
          branches.each do |branch|
            gitlog = []
            Dir.chdir(reponame) do
              `git checkout #{branch}`
              `git log --oneline -n #{LOG_MAX}`.split("\n").each do |line|
                gitlog << line.split("\s", 2)
              end
              gitlog.each do |val|
                comm, msg = val
                @commitlog["#{reponame}-#{comm}"] = `git show #{comm}`
              end
            end
            @gitlog["#{reponame}-#{branch}"] = {:url => url, :gitlog => gitlog}
          end
        end
      end
    end
  end

  def report
    load_files
    analyze_git

    if File.exist? REPORT_DIR
      FileUtils.rm_r REPORT_DIR
    end
    FileUtils.mkdir_p REPORT_DIR

=begin
    @reports.each do |id, reports|
      filepath = File.join(REPORT_DIR, "#{id}.html")
      File.open(filepath, 'w') do |fp|
        puts filepath
        fp.write ERB.new(File.open(@buildreport_template).read).result(binding)
      end
    end
=end

    @gitlog.each do |reponame, val|
      gitlog = val[:gitlog]
      url    = val[:url]
      gitlog.each do |log|
        id = "#{reponame}-#{log[0]}"
        reports = @reports[id]
        filepath = File.join(REPORT_DIR, "#{id}.html")
        if reports && (not File.exist?(filepath))
          File.open(filepath, 'w') do |fp|
            puts filepath
            fp.write ERB.new(File.open(@buildreport_template).read).result(binding)
          end
        end
      end
      filepath = File.join(REPORT_DIR, "#{reponame}.html")
      File.open(filepath, 'w') do |fp|
        fp.write ERB.new(File.open(@repository_template).read).result(binding)
      end
    end

    repofilepath = File.join(REPORT_DIR, "#{@gitlog.keys.first}.html")
    filepath = File.join(REPORT_DIR, "index.html")
    File.open(filepath, 'w') do |fp|
      fp.write File.open(repofilepath).read
    end

    FileUtils.rm_r @workdir

    "done."
  end

  private
  def mktmpdir(mode = 'gitlog', limit = 3)
    tmpdir = File.join(TMPDIR, "#{Time.now.strftime("%Y%m%d%H%M%S")}-#{$$}-#{mode}")
    if File.exist? tmpdir
      mktmpdir(mode, limit - 1)
    else
      FileUtils.mkdir_p(tmpdir)
    end

    tmpdir
  end
end

