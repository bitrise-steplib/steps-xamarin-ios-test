require_relative './analyzer'
require_relative './common_constants'

class Builder
  def initialize(path, configuration, platform, project_type_filter=nil)
    raise 'Empty path provided' if path.to_s == ''
    raise "File (#{path}) not exist" unless File.exist? path

    raise 'No configuration provided' if configuration.to_s == ''
    raise 'No platform provided' if platform.to_s == ''

    @path = path
    @configuration = configuration
    @platform = platform
    @project_type_filter = project_type_filter || [Api::IOS, Api::ANDROID, Api::MAC]

    @analyzer = Analyzer.new
    @analyzer.analyze(@path)
  end

  def build
    build_commands = @analyzer.build_commands(@configuration, @platform, @project_type_filter)
    if build_commands.empty?
      # No iOS or Android application found to build
      # Switching to framework building
      build_commands << @analyzer.build_solution_command(@configuration, @platform)
    end

    build_commands.each do |build_command|
      puts
      puts "\e[34m#{build_command}\e[0m"
      puts

      raise 'Build failed' unless system(build_command.join(' '))
    end

    @generated_files = @analyzer.collect_generated_files(@configuration, @platform, @project_type_filter)
  end

  def build_solution
    build_command = @analyzer.build_solution_command(@configuration, @platform)

    puts
    puts "\e[34m#{build_command}\e[0m"
    puts

    raise 'Build failed' unless system(build_command.join(' '))

    @generated_files = @analyzer.collect_generated_files(@configuration, @platform, @project_type_filter)
  end

  def build_test
    test_commands, errors = @analyzer.build_test_commands(@configuration, @platform, @project_type_filter)

    if test_commands.nil? || test_commands.empty?
      errors = ['Failed to create test command'] if errors.empty?
      raise errors.join("\n")
    end

    test_commands.each do |test_command|
      puts
      puts "\e[34m#{test_command}\e[0m"
      puts

      raise 'Test failed' unless system(test_command.join(' '))
    end

    @generated_files = @analyzer.collect_generated_files(@configuration, @platform, @project_type_filter)
  end

  def run_nunit_tests(options = nil)
    test_commands, errors = @analyzer.nunit_test_commands(@configuration, @platform, options)

    if test_commands.nil? || test_commands.empty?
      errors = ['Failed to create test command'] if errors.empty?
      raise errors.join("\n")
    end

    test_commands.each do |test_command|
      puts
      puts "\e[34m#{test_command}\e[0m"
      puts

      raise 'Test failed' unless system(test_command.join(' '))
    end
  end

  def generated_files
    @generated_files
  end
end
