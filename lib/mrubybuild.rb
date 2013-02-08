#!/usr/bin/env ruby
# --*-- encoding: utf-8 --*--

require 'rubygems'
require 'uri'
require 'fileutils'
require 'open-uri'
require 'logger'
require 'zipruby'
require 'popen4'
require 'yaml'

if $logger.nil?
  $logger = Logger.new(STDOUT)
  $logger.level = Logger::DEBUG
end

DIR = File.dirname(__FILE__)
ENV['LANG'] = 'C'

class MrubyBuild
  TMPDIR = File.expand_path('../../tmp', __FILE__)
  RESULT_DIR = File.expand_path('../../result', __FILE__)

  def initialize(repository = 'iij/mruby', commit = 'iij', opts = {})
    @repository = repository
    @commit     = commit
    @zipball_path = nil

    @opts = {
      :ruby  => (ENV['RUBY']  or ENV['ruby']  or 'ruby'),
      :gcc   => (ENV['GCC']   or ENV['gcc']   or 'gcc'),
      :make  => (ENV['MAKE']  or ENV['make']  or 'make'),
      :bison => (ENV['BISON'] or ENV['bison'] or 'bison'),
    }

    @result = {
      :date => Time.now,
    }
  end

  def env
    e = {}
    e[:gcc] = sh "#{@opts[:gcc]} --version"
    e[:gcc][:path] = @opts[:gcc]
    e[:make] = sh "#{@opts[:make]} --version"
    e[:make][:path] = @opts[:make]
    e[:bison] = sh "#{@opts[:bison]} --version"
    e[:bison][:path] = @opts[:bison]
    e
  end

  def self.url(url)
    url = URI.parse(url)
    paths = url.path.split('/')
    if url.host == 'github.com' and paths[3] == 'zipball'
      repository = paths[1, 2].join('/')
      commit     = paths[4]
      self.new(repository, commit)
    else
      raise ArgumentError.new("url should be github.com/**/**/zipball/** format.")
    end
  end

  attr_accessor :repository, :commit, :zipball_path, :workdir

  def ball_id
    "%s-%s-%s" % [@repository.split('/'), @commit].flatten
  end

  def hostname
    ENV['NAME'] or ENV['name'] or `hostname -s`.chomp.split('.').first
  end

  def zipball_url
    URI::Generic.build({
      :scheme => 'https',
      :host => 'github.com',
      :path => "/#{@repository}/zipball/#{@commit}"
    }).to_s
  end

  def download
    if @zipball_path and File.exist?(@zipball_path)
      $logger.debug('download: skip; file already exists.')
    elsif $offline_mode
      $logger.debug('download: skip cause offline-mode')
    else
      $logger.debug('download: start URL:' + zipball_url)
      tmpdir = mktmpdir(:download)
      @zipball_path = File.join(tmpdir, 'zipball')
      File.open(@zipball_path, 'wb') do |fp|
        fp.write open(zipball_url).read
      end
      $logger.debug("download: done. #{File.size(@zipball_path)}bytes fetched.")
    end

    self
  end

  def unzip
    if @zipball_path.nil? or (not File.exist?(@zipball_path))
      $logger.info("zipball is not found. will downloading...")
      download
      if @zipball_path.nil? or (not File.exist?(@zipball_path))
        raise "zipball can't fetched.."
      end
    end
    zipball_expand_path = File.expand_path(@zipball_path)
    $logger.info("zipball: #{zipball_expand_path} will extract.")

    tmpdir = mktmpdir(:build)
    Dir.chdir(tmpdir) do
      Zip::Archive.open(zipball_expand_path) do |ar|
        ar.each do |zf|
          if zf.directory?
            FileUtils.mkdir_p(zf.name)
          else
            dirname = File.dirname(zf.name)

            FileUtils.mkdir_p(dirname) unless File.exist?(dirname)
            open(zf.name, 'wb') do |f|
              f << zf.read
            end

            if zf.name =~ /\.sh$/ or zf.name =~ /minirake$/
              FileUtils.chmod(0755, zf.name)
            end
          end
        end
      end
      $logger.info("unzip done.")
    end

    @workdir = Dir.glob("#{tmpdir}/*").sort.first
    ball_id_ = @workdir.split("#{tmpdir}/").last
    if ball_id_ != ball_id
      $logger.info("ball id change from #{ball_id} to #{ball_id_}")
      @commit = ball_id_.split('-').last
    end

    self
  end

  def sh(*cmd)
    result = {}
    result[:status_info] = POpen4::popen4(*cmd) do |stdout, stderr, stdin, pid|
      result[:stdout] = stdout.read.strip
      result[:stderr] = stderr.read.strip
    end
    result[:status] = result[:status_info].success? ? 'success' : 'failed'
    result
  end

  def build(build_otps = {})
    workdir = @workdir.sub("#{DIR}/", '')
    Dir.chdir(@workdir) do
      @result[:id] = ball_id
      @result[:zipball_url] = zipball_url
      if ENV['BEFORE_MAKE']
        $logger.debug("exec before make: #{ENV['BEFORE_MAKE']}")
        sh ENV['BEFORE_MAKE']
      end
      # make
      $logger.info("make on #{workdir}")
      @result[:make] = sh "#{@opts[:ruby]} ./minirake"
      $logger.debug("make done on #{workdir} (#{@result[:make][:status]})")
      # make test
      $logger.info("make test on #{workdir}")
      @result[:make_test] = sh "#{@opts[:ruby]} ./minirake test"
      {
        :mrubytest_rb  => 'test/mrubytest.rb.report',
        :mrubytest_mrb => 'test/mrubytest.mrb.report',
      }.each do |key, filepath|
        if File.exist? filepath
          @result[:make_test][key] = File.open(filepath).read
        end
      end
      $logger.debug("make test done on #{workdir} (#{@result[:make_test][:status]})")
      if File.exist?('test/posix')
        # posix test
        $logger.info("posix test on #{workdir}")
        @result[:posix_test] = sh "./test/posix/all.sh"
        $logger.debug("posix test done on #{workdir} (#{@result[:posix_test][:status]})")
      end
    end

    @result[:filesize] = fetch_filesize

    self
  end

  def fetch_filesize
    data = {}
    %w(bin/mruby bin/mrbc bin/mirb lib/libmruby.a lib/libmruby_core.a test/mrbtest).each do |f|
      path = File.join(@workdir, 'build', 'host',  f)
      if File.exist?(path)
        tmp = File.join('/tmp', "mruby.filesize.#{$$}")
        File.copy path, tmp
        `strip #{tmp}`
        data[f] = File.size(tmp)
        File.delete tmp
      end
    end
    data
  end

  def result_filename
    "#{hostname}.#{ball_id}.yml"
  end

  def result_filepath
    File.join(RESULT_DIR, result_filename)
  end

  def result_exist?
    File.exist? result_filepath
  end

  def save(filename = nil)
    if @result.nil?
      $logger.info("can't save.")
      return
    end
    if filename.nil?
      filename = result_filename
    end
    if not File.exist? RESULT_DIR
      FileUtils.mkdir_p RESULT_DIR
    end

    @result[:repository] = @repository
    @result[:commit]     = @commit
    @result[:ball_id]    = ball_id
    @result[:hostname]   = hostname
    @result[:env]        = env
    @result[:opts]       = @opts

    YAML.dump(@result, File.open(result_filepath, 'w'))
    $logger.info("save done: #{filename}")

    cleanup  unless ARGV.include?('--no-clean')

    self
  end

  def cleanup
    $logger.debug("cleanup start.")
    if File.exist? File.dirname(@workdir)
      $logger.debug("workdir:#{File.dirname @workdir} is cleaning...")
      FileUtils.rm_r File.dirname(@workdir)
    else
      $logger.debug("workdir:#{File.dirname @workdir} is not found. cleanup skip.")
    end
    if File.exist? File.dirname(@zipball_path)
      $logger.debug("workdir:#{File.dirname @zipball_path} is cleaning...")
      FileUtils.rm_r File.dirname(@zipball_path)
    else
      $logger.debug("workdir:#{File.dirname @workdir} is not found. cleanup skip.")
    end
    $logger.debug("cleanup done.")
  end

  private
  def mktmpdir(mode = 'download', limit = 3)
    tmpdir = File.join(TMPDIR, "#{Time.now.strftime("%Y%m%d%H%M%S")}-#{$$}-#{mode}")
    if File.exist? tmpdir
      mktmpdir(mode, limit - 1)
    else
      FileUtils.mkdir_p(tmpdir)
    end

    tmpdir
  end
end

if __FILE__ == $0

end
