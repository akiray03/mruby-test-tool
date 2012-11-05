# --*-- encoding: utf-8 --*--

ENV["MRUBY_BUILD_TMP_DIR"] = File.join(File.dirname(__FILE__), '../tmp')
require 'fileutils'
require 'mrubybuild'

describe MrubyBuild, 'with default init' do
  before :all do
    if File.exist? ENV["MRUBY_BUILD_TMP_DIR"]
      FileUtils.rm_r ENV["MRUBY_BUILD_TMP_DIR"]
    end
  end

  describe 'with default value' do
    before do
      @m = MrubyBuild.new
    end

    it '#class' do
      @m.should be_a(MrubyBuild)
    end

    it '#repository' do
      @m.repository.should == 'iij/mruby'
    end

    it '#commit' do
      @m.commit.should == 'iij'
    end

    it "#zipball_url" do
      @m.zipball_url.should == 'https://github.com/iij/mruby/zipball/iij'
    end

    it '#ball_id' do
      @m.ball_id.should == 'iij-mruby-iij'
    end

    it "#download" do
      before = Dir.glob("#{MrubyBuild::TMPDIR}/*")
      @m.download
      after  = Dir.glob("#{MrubyBuild::TMPDIR}/*")

      (after - before).size.should == 1
      dir = (after-before).first
      File.exist?(File.join(dir, 'zipball')).should be_true
    end
  end

  describe 'with custom url' do
    before do
      @m = MrubyBuild.url('http://github.com/mruby/mruby/zipball/master')
    end

    it '#class' do
      @m.should be_a(MrubyBuild)
    end

    it '#repository' do
      @m.repository.should == 'mruby/mruby'
    end

    it '#commit' do
      @m.commit.should == 'master'
    end

    it "#zipball_url" do
      @m.zipball_url.should == 'https://github.com/mruby/mruby/zipball/master'
    end

    it '#ball_id' do
      @m.ball_id.should == 'mruby-mruby-master'
    end

    it "#download" do
      before = Dir.glob("#{MrubyBuild::TMPDIR}/*")
      @m.download
      after  = Dir.glob("#{MrubyBuild::TMPDIR}/*")

      (after - before).size.should == 1
      dir = (after-before).first
      File.exist?(File.join(dir, 'zipball')).should be_true
    end
  end

  describe 'with local file' do
    before do
      @m = MrubyBuild.new
      @m.zipball_path = File.join(File.dirname(__FILE__), 'iij.zip')
    end

    it '#class' do
      @m.should be_a(MrubyBuild)
    end

    it '#repository' do
      @m.repository.should == 'iij/mruby'
    end

    it '#commit' do
      @m.commit.should == 'iij'
    end

    it "#zipball_url" do
      @m.zipball_url.should == 'https://github.com/iij/mruby/zipball/iij'
    end

    it '#ball_id' do
      @m.ball_id.should == 'iij-mruby-iij'
    end

    it "#download" do
      before = Dir.glob("#{MrubyBuild::TMPDIR}/*")
      @m.download
      after  = Dir.glob("#{MrubyBuild::TMPDIR}/*")

      before.size.should == after.size
    end
  end

end
