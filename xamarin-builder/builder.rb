require_relative './analyzer'

class Builder
  def initialize(path, configuration, platform, project_type_filter=nil)
    fail 'Empty path provided' if path.to_s == ''
    fail "File (#{path}) not exist" unless File.exist? path

    fail 'No configuration provided' if configuration.to_s == ''
    fail 'No platform provided' if platform.to_s == ''

    @path = path
    @configuration = configuration
    @platform = platform
    @project_type_filter = project_type_filter || ['ios', 'android']
  end

  def build
    analyzer = Analyzer.new
    analyzer.analyze(@path)

    build_commands = analyzer.build_commands(@configuration, @platform, @project_type_filter)

    build_commands.each do |build_command|
      puts
      puts "\e[32m#{build_command}\e[0m"
      puts

      raise 'Build failed' unless system(build_command)
    end

    @generated_files = analyzer.collect_generated_files(@configuration, @platform, @project_type_filter)
  end

  def build_test
    analyzer = Analyzer.new
    analyzer.analyze(@path)

    test_command = analyzer.test_commands(@configuration, @platform)

    puts
    puts "\e[32m#{test_command}\e[0m"
    puts

    raise 'Build failed' unless system(test_command)

    @generated_files = analyzer.collect_generated_files(@configuration, @platform, @project_type_filter)
  end

  def generated_files
    @generated_files
  end
end
