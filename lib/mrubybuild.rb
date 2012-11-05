#!/usr/bin/env ruby
# --*-- encoding: utf-8 --*--

require 'uri'
require 'fileutils'
require 'open-uri'
require 'logger'
require 'zipruby'

if $logger.nil?
  $logger = Logger.new(STDOUT)
  $logger.level = Logger::DEBUG
end

class MrubyBuild
  TMPDIR = (ENV["MRUBY_BUILD_TMP_DIR"] or File.join(File.dirname(__FILE__), 'tmp'))

  def initialize(repository = 'iij/mruby', commit = 'iij')
    @repository = repository
    @commit     = commit
    @zipball_path = nil
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

  attr_accessor :repository, :commit, :zipball_path

  def ball_id
    "%s-%s-%s" % [@repository.split('/'), @commit].flatten
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
      $logger.debug('download: start')
      tmpdir = mkdir(:download)
      @zipball_path = File.join(tmpdir, 'zipball')
      File.open(@zipball_path, 'wb') do |fp|
        fp.write open(zipball_url).read
      end
      $logger.debug("download: done. #{File.size(@zipball_path)}bytes fetched.")
    end
  end

  def unzip
    if @zipball_path.nil? or (not File.exist?(@zipball_path))
      download
      if @zipball_path.nil? or (not File.exist?(@zipball_path))
        raise "zipball can't fetched.."
      end
    end

    Dir.chdir(File.dirname(@zipball_path)) do
      Zip::Archive.open(File.basename @zipball_path) do |ar|
        ar.each do |zf|
          if zf.directory?
            FileUtils.mkdir_p(zf.name)
          else
            dirname = File.dirname(zf.name)

            FileUtils.mkdir_p(dirname) unless File.exist?(dirname)
            open(zf.name, 'wb') do |f|
              f << zf.read
            end
          end
        end
      end
    end
  end

  private
  def mkdir(mode = 'download', limit = 3)
    tmpdir = File.join(TMPDIR, "#{mode}-#{ball_id}-#{Time.now.to_i}")
    if File.exist? tmpdir
      mkdir(mode, limit - 1)
    else
      FileUtils.mkdir_p(tmpdir)
    end

    tmpdir
  end
end

if __FILE__ == $0

end
