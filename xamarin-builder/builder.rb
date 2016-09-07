require 'tmpdir'
require 'open-uri'
require 'open3'

require_relative './analyzer'
require_relative './common_constants'
require_relative './timer'

class Builder
  def initialize(path, configuration, platform, project_type_filter=nil)
    raise 'Empty path provided' if path.to_s == ''
    raise "File (#{path}) not exist" unless File.exist? path

    raise 'No configuration provided' if configuration.to_s == ''
    raise 'No platform provided' if platform.to_s == ''

    raise 'project_type_filter should be an Array of Strings' if project_type_filter && !project_type_filter.is_a?(Array)

    @path = path
    @configuration = configuration
    @platform = platform
    @project_type_filter = project_type_filter || [Api::IOS, Api::TVOS, Api::ANDROID, Api::MAC]

    @analyzer = Analyzer.new
    @analyzer.analyze(@path)
  end

  # README:
  # This method will run `mdtool build` in diagnostic mode.
  # If mdtool will hang trying to load projects its process will be killed
  # and stack trace for each thread of mdtool will be printed to stdout.
  # Issue on Bugzilla: https://bugzilla.xamarin.com/show_bug.cgi?id=42378

  # List of things to be removed as as soon as #42378 will be resolved:
  # 1) run_mdtool_in_diagnostic_mode method
  # 2) hijack_process method
  # 3) MDTOOL_PATH constant in Builder class
  # 4) Entire Timer class
  # 5) if/else logic in Builder.build

  MDTOOL_PATH = "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\""

  def run_mdtool_in_diagnostic_mode(mdtool_build_command, retry_on_hang = true)
    pid = nil
    timeout = false

    # force kill process if kill -QUIT does not stops it
    force_timer = Timer.new(60) do
      puts
      puts "\e[33mForce terminating...\e[0m"

      Process.kill('SIGKILL', pid)
    end

    # kill process if hangs on Loading projects...
    timer = Timer.new(300) do
      timeout = true

      puts
      puts "\e[33mCommand timed out, terminating...\e[0m"

      force_timer.start

      Process.kill('QUIT', pid)
    end

    return_value = nil

    Open3.popen3(mdtool_build_command.join(' ')) do |_, stdout, _, wait_thr|
      pid = wait_thr.pid

      stdout.each do |line|
        puts line

        timer.stop if timer.running?
        timer.start if line.include? 'Loading projects'
      end

      return_value = wait_thr.value
    end

    force_timer.stop

    success = return_value.success?

    if timeout
      unless retry_on_hang
        puts "\e[31mCommand timed out\e[0m"
        return false
      end

      puts
      puts "\e[33mRertying command:\e[0m"
      puts "\e[34m#{mdtool_build_command}\e[0m"
      puts

      success = run_mdtool_in_diagnostic_mode(mdtool_build_command, false)
    end

    success
  end

  def build(retry_on_hang = true)
    build_commands = @analyzer.build_commands(@configuration, @platform, @project_type_filter, nil)
    if build_commands.empty?
      # No iOS or Android application found to build
      # Switching to framework building
      build_commands << @analyzer.build_solution_command(@configuration, @platform)
    end

    build_commands.each do |build_command|
      if ([MDTOOL_PATH, 'build', 'archive'] & build_command).any?
        puts
        puts 'Run build in diagnostic mode:'
        puts "\e[34m#{build_command}\e[0m"
        puts

        raise 'Build failed' unless run_mdtool_in_diagnostic_mode(build_command, retry_on_hang)
      else
        puts
        puts "\e[34m#{build_command}\e[0m"
        puts

        raise 'Build failed' unless system(build_command.join(' '))
      end
    end

    @generated_files = @analyzer.collect_generated_files(@configuration, @platform, @project_type_filter)
  end

  def build_solution(retry_on_hang = true)
    build_command = @analyzer.build_solution_command(@configuration, @platform)
    if ([MDTOOL_PATH, 'build', 'archive'] & build_command).any?
      puts
      puts 'Run build in diagnostic mode:'
      puts "\e[34m#{build_command}\e[0m"
      puts

      raise 'Build failed' unless run_mdtool_in_diagnostic_mode(build_command, retry_on_hang)
    else
      puts
      puts "\e[34m#{build_command}\e[0m"
      puts

      raise 'Build failed' unless system(build_command.join(' '))
    end

    @generated_files = @analyzer.collect_generated_files(@configuration, @platform, @project_type_filter)
  end

  def build_test(retry_on_hang = true)
    test_commands, errors = @analyzer.build_test_commands(@configuration, @platform, @project_type_filter)

    if test_commands.nil? || test_commands.empty?
      errors = ['Failed to create test command'] if errors.empty?
      raise errors.join("\n")
    end

    test_commands.each do |test_command|
      if ([MDTOOL_PATH, 'build', 'archive'] & test_command).any?
        puts
        puts 'Run build in diagnostic mode:'
        puts "\e[34m#{test_command}\e[0m"
        puts

        raise 'Test failed' unless run_mdtool_in_diagnostic_mode(test_command, retry_on_hang)
      else
        puts
        puts "\e[34m#{test_command}\e[0m"
        puts

        raise 'Test failed' unless system(test_command.join(' '))
      end
    end

    @generated_files = @analyzer.collect_generated_files(@configuration, @platform, @project_type_filter)
  end

  def run_nunit_tests(options = nil, retry_on_hang = true)
    test_commands, errors = @analyzer.nunit_test_commands(@configuration, @platform, options)

    if test_commands.nil? || test_commands.empty?
      errors = ['Failed to create test command'] if errors.empty?
      raise errors.join("\n")
    end

    test_commands.each do |test_command|
      if ([MDTOOL_PATH, 'build', 'archive'] & test_command).any?
        puts
        puts 'Run build in diagnostic mode:'
        puts "\e[34m#{test_command}\e[0m"
        puts

        raise 'Test failed' unless run_mdtool_in_diagnostic_mode(test_command, retry_on_hang)
      else
        puts
        puts "\e[34m#{test_command}\e[0m"
        puts

        raise 'Test failed' unless system(test_command.join(' '))
      end
    end
  end

  def run_nunit_lite_tests(retry_on_hang = true)
    touch_unit_server = get_touch_unit_server

    logfile = 'tests.log'
    test_commands, errors = @analyzer.nunit_light_test_commands(@configuration, @platform, touch_unit_server, logfile)

    if test_commands.nil? || test_commands.empty?
      errors = ['Failed to create test command'] if errors.empty?
      raise errors.join("\n")
    end

    app_file = nil
    test_commands.each do |test_command|
      test_command.collect! { |element| (element == '--launchsim') ? "--launchsim #{app_file}" : element } if test_command.include?("\"#{touch_unit_server}\"") && !app_file.nil?

      if ([MDTOOL_PATH, 'build', 'archive'] & test_command).any?
        puts
        puts 'Run build in diagnostic mode:'
        puts "\e[34m#{test_command}\e[0m"
        puts

        raise 'Test failed' unless run_mdtool_in_diagnostic_mode(test_command, retry_on_hang)
      else
        puts
        puts "\e[34m#{test_command}\e[0m"
        puts

        raise 'Test failed' unless system(test_command.join(' '))
      end

      next unless test_command.include? MDTOOL_PATH

      @generated_files = @analyzer.collect_generated_files(@configuration, @platform, @project_type_filter)
      @generated_files.each do |_, project_output|
        app_file = project_output[:app] if project_output[:api] == Api::IOS && project_output[:app]
      end
    end

    results = process_touch_unit_logs(logfile)

    # remove logs file
    FileUtils.remove_entry logfile

    raise 'Test failed' if results['Failed'] != '0'
  end

  def generated_files
    @generated_files
  end

  private

  def get_touch_unit_server
    # Use preinstalled Touch.Server.exe if exist
    preinstalled_touch_unit_server = ENV['TOUCH_SERVER_PATH']
    if preinstalled_touch_unit_server && !preinstalled_touch_unit_server.empty? && File.exist?(preinstalled_touch_unit_server)
      return preinstalled_touch_unit_server
    end

    puts 'preinstalled Touch.Server.exe missing, downloading it...'

    # Download Touch.Server.exe
    touch_unit_server_pth = File.join(Dir.tmpdir, 'Touch.Server.exe')
    touch_unit_server_url = 'https://github.com/bitrise-io/Touch.Unit/releases/download/0.9.0/Touch.Server.exe'

    File.open(touch_unit_server_pth, 'wb') do |saved_file|
      # the following "open" is provided by open-uri
      open(touch_unit_server_url, 'rb') do |read_file|
        saved_file.write(read_file.read)
      end
    end

    touch_unit_server_pth
  end

  def process_touch_unit_logs(logs_path)
    results = {}

    raise 'Cant find test logs file' unless File.exist?(logs_path)

    File.open(logs_path, 'r') do |f|
      f.each_line do |line|
        puts line

        next unless line.start_with?('Tests run')

        line.gsub(/[a-zA-z]*: [0-9]*/) do |s|
          s.delete!(' ')
          test_result = s.split(/:/)

          results[test_result.first] = test_result.last
        end
      end
    end

    results
  end
end
