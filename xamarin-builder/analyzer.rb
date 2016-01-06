MONO_ANDROID_API_NAME = 'Mono.Android'
MONOTOUCH_API_NAME = 'monotouch'
XAMARIN_IOS_API_NAME = 'Xamarin.iOS'
XAMARIN_UITEST_API = 'Xamarin.UITest'

# define class ProjectAnalyzer
class ProjectAnalyzer

  CSPROJ_EXT = '.csproj'

  def initialize(path)
    fail 'Empty path provided' if path.to_s == ''
    fail "File (#{path}) not exist" unless File.exist? path

    ext = File.extname(path)
    fail "Path (#{path}) is not a csproj path, extension should be: #{CSPROJ_EXT}" if ext != CSPROJ_EXT

    @path = path
  end

  def analyze(configuration, platform)
    project_to_build = {
        path: @path,
        configuration: configuration,
        platform: platform
    }

    # Collect project information

    analyzer = ProjectAnalyzer.new(project_to_build[:path])

    output_path = analyzer.output_path(project_to_build[:configuration], project_to_build[:platform])
    api = analyzer.xamarin_api
    is_test = (api == XAMARIN_UITEST_API)
    build_ipa = false
    if api == MONOTOUCH_API_NAME || api == XAMARIN_IOS_API_NAME
      build_ipa = analyzer.allowed_to_build_ipa(project_to_build[:configuration], project_to_build[:platform])
    end
    sign_apk = false
    if api == MONO_ANDROID_API_NAME
      sign_apk = analyzer.allowed_to_sign_android(project_to_build[:configuration], project_to_build[:platform])
    end

    related_test_project = ''
    if !is_test
      solution = SolutionAnalyzer.new(solution_path).analyze
      solution[:test_projects].each do |test_project_path|
        referred_project_path = ProjectAnalyzer.new(test_project_path[:path]).referred_project_path
        related_test_project = test_project_path[:path] if referred_project_path == @path
      end
    end

    project_to_build[:api] = api
    project_to_build[:output_path] = output_path
    project_to_build[:is_test] = is_test
    project_to_build[:build_ipa] = build_ipa
    project_to_build[:sign_apk] = sign_apk
    project_to_build[:related_test_project] = related_test_project unless related_test_project == ''

    project_to_build
  end

  def solution_path
    # <ProjectTypeGuids>{FEACFBD2-3405-455C-9665-78FE426C6842};{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}</ProjectTypeGuids>
    project_ids_regexp = '<ProjectTypeGuids>(?<ids>.*)<\/ProjectTypeGuids>'

    solution_id = ''

    File.open(@path).each do |line|
      match = line.match(project_ids_regexp)
      if match && match.captures && match.captures.count == 1
        ids = match.captures[0].split(';')

        prepared_ids = []
        ids.each do |id|
          id[0] = ''
          id[id.length-1] = ''
          prepared_ids << id
        end

        solution_id = prepared_ids.last
      end
    end

    if solution_id
      root_dir = File.dirname(@path)
      root_dir = File.dirname(root_dir)

      solutions = Dir[File.join(root_dir, '/*.sln')]

      solutions.each do |solution|
        found_solution_id = SolutionAnalyzer.new(solution).solution_id
        return solution if found_solution_id == solution_id
      end
    end

    nil
  end

  def referred_project_path
    # <ProjectReference Include="..\CreditCardValidator.Droid\CreditCardValidator.Droid.csproj">
    referred_project_regexp = '<ProjectReference Include="(?<project>.*)">'

    File.open(@path).each do |line|
      match = line.match(referred_project_regexp)
      if match && match.captures && match.captures.count == 1
        referred_project_path = match.captures[0].strip.gsub(/\\/, '/')
        project_dir = File.dirname(@path)

        return File.expand_path(referred_project_path, project_dir)
      end
    end

    nil
  end

  def output_path(configuration, platform)
    # <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|iPhone' ">
    config_regexp = '<PropertyGroup Condition=" \'\$\(Configuration\)\|\$\(Platform\)\' == \'(?<config>.*)\' ">'

    # <OutputPath>bin\Debug</OutputPath>
    output_path_regexp = '<OutputPath>(?<path>.*)<\/OutputPath>'

    related_config_start = false

    File.open(@path).each do |line|
      match = line.match(config_regexp)
      if match && match.captures && match.captures.count == 1
        found_config = match.captures[0]
        found_configuration, found_platform = found_config.split('|')

        if found_configuration == configuration
          related_config_start = true if found_platform == platform

          found_platform = found_platform.downcase
          related_config_start = true if found_platform == 'anycpu' || found_platform == 'any cpu'
        end
      end

      next unless related_config_start

      match = line.match(output_path_regexp)
      return match.captures[0].strip.gsub(/\\/, '/') if match && match.captures && match.captures.count == 1
    end

    nil
  end

  def allowed_to_build_ipa(configuration, platform)
    # <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|iPhone' ">
    config_regexp = '<PropertyGroup Condition=" \'\$\(Configuration\)\|\$\(Platform\)\' == \'(?<config>.*)\' ">'

    config = configuration + '|' + platform
    related_config_start = false

    File.open(@path).each do |line|
      match = line.match(config_regexp)
      if match && match.captures && match.captures.count == 1
        found_config = match.captures[0]

        related_config_start = (found_config == config)
      end

      next unless related_config_start

      downcase_line = line.downcase
      return true if downcase_line.include? '<buildipa>true</buildipa>'
      return true if downcase_line.include? '<ipapackagename>'
    end

    false
  end

  def allowed_to_sign_android(configuration, platform)
    # <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|AnyCPU' ">
    config_regexp = '<PropertyGroup Condition=" \'\$\(Configuration\)\|\$\(Platform\)\' == \'(?<config>.*)\' ">'
    config = configuration + '|' + platform
    related_config_start = false

    File.open(@path).each do |line|
      match = line.match(config_regexp)
      if match && match.captures && match.captures.count == 1
        found_config = match.captures[0]

        related_config_start = (found_config == config)
      end

      next unless related_config_start

      return true if line.downcase.include? '<androidkeystore>true</androidkeystore>'
    end

    false
  end

  def xamarin_api
    if File.file?(@path)
      lines = File.readlines(@path)

      return 'Mono.Android' if lines.grep(/Include="Mono.Android"/).size > 0
      return 'monotouch' if lines.grep(/Include="monotouch"/).size > 0
      return 'Xamarin.iOS' if lines.grep(/Include="Xamarin.iOS"/).size > 0
      return 'Xamarin.UITest' if lines.grep(/Include="Xamarin.UITest"/).size > 0
    end

    nil
  end

end

# define class SolutionAnalyzer
class SolutionAnalyzer

  SLN_EXT = '.sln'

  def initialize(path)
    fail 'Empty path provided' if path.to_s == ''
    fail "File (#{path}) not exist" unless File.exist? path

    ext = File.extname(path)
    fail "Path (#{path}) is not a solution path, extension should be: #{SLN_EXT}" if ext != SLN_EXT

    @path = path
  end

  def solution_id
    # Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "CreditCardValidator", "CreditCardValidator\CreditCardValidator.csproj", "{99A825A6-6F99-4B94-9F65-E908A6347F1E}"
    p_regexp = 'Project\("{(?<solution_id>.*)}"\) = "(?<project_name>.*)", "(?<project_path>.*)", "{(?<project_id>.*)}"'

    File.open(@path).each do |line|
      match = line.match(p_regexp)
      if match && match.captures && match.captures.count == 4
        return match.captures[0]
      end
    end
  end

  def collect_projects(configuration, platform)

    # Collect projects

    projects = []

    solution = SolutionAnalyzer.new(@path).analyze
    solution[:projects].each do |project|
      mapping = project[:mapping]
      config = mapping["#{configuration}|#{platform}"]
      fail "No mapping found for config: #{configuration}|#{platform}" unless config

      mapped_configuration, mapped_platform = config.split('|')
      fail "No configuration, platform found for config: #{config}" unless configuration || platform

      projects << {
          path: project[:path],
          configuration: mapped_configuration,
          platform: mapped_platform
      }
    end

    # Collect project information

    projects_to_build = []

    projects.each do |project_to_build|
      projects_to_build << ProjectAnalyzer.new(project_to_build[:path]).analyze(configuration, platform)
    end

    projects_to_build
  end

  def analyze
    solution = {}
    projects = {}

    base_directory = File.dirname(@path)

    # Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "CreditCardValidator", "CreditCardValidator\CreditCardValidator.csproj", "{99A825A6-6F99-4B94-9F65-E908A6347F1E}"
    p_regexp = 'Project\("{(?<solution_id>.*)}"\) = "(?<project_name>.*)", "(?<project_path>.*)", "{(?<project_id>.*)}"'

    is_next_s_config = false
    s_configs_start = 'GlobalSection(SolutionConfigurationPlatforms) = preSolution'
    s_configs_end = 'EndGlobalSection'

    is_next_p_config = false
    p_configs_start = 'GlobalSection(ProjectConfigurationPlatforms) = postSolution'
    p_configs_end = 'EndGlobalSection'
    p_config_regexp = '{(?<project_id>.*)}.(?<solution_configuration_platform>.*|.*) = (?<project_configuration_platform>.*)'

    File.open(@path).each do |line|
      #
      # Collect Projects
      match = line.match(p_regexp)
      if match && match.captures && match.captures.count == 4
        solution['projects'] = [] unless solution['projects']

        # solution_id =  match.captures[0]
        # project_name = match.captures[1]
        project_path = match.captures[2].strip.gsub(/\\/, '/')
        project_path = File.join(base_directory, project_path)

        next unless File.exist? project_path

        project_id = match.captures[3]

        received_api = ProjectAnalyzer.new(project_path).xamarin_api
        unless received_api.nil?
          solution['projects'] << {
              'id' => project_id,
              'path' => project_path,
              'api' => received_api
          }

          next
        end
      end

      #
      # Collect SolutionConfigurationPlatforms
      is_next_s_config = false if line.include?(s_configs_end) && is_next_s_config == true

      if is_next_s_config
        begin
          config = line.split('=')[1].strip!

          solution['configs'] = [] unless solution['configs']
          solution['configs'] << config

          next
        rescue
          fail "Failed to parse configuration: #{line}"
        end
      end

      is_next_s_config = true if line.include?(s_configs_start)

      #
      # Collect ProjectConfigurationPlatforms
      is_next_p_config = false if line.include?(p_configs_end) && is_next_p_config == true

      if is_next_p_config
        match = line.match(p_config_regexp)
        if match && match.captures && match.captures.count == 3
          project_id = match.captures[0]

          s_config = match.captures[1].strip
          if s_config.include? '.'
            s_config = s_config.split('.')[0]
          end
          p_config = match.captures[2].strip.gsub(' ', '')

          projects["#{project_id}"] = {} unless projects["#{project_id}"]
          projects["#{project_id}"][s_config] = p_config
        end

        next
      end

      is_next_p_config = true if line.include? p_configs_start
    end

    ret_projects = []
    ret_test_projects = []

    s_projects = solution['projects']
    s_projects.each do |proj|
      id = proj['id']
      mapping = projects["#{id}"]
      path = proj['path']
      api = proj['api']

      proj['mapping'] = mapping

      if api == XAMARIN_UITEST_API
        ret_test_projects << {
            path: path,
            mapping: mapping,
            api: api
        }
      else
        ret_projects << {
            path: path,
            mapping: mapping,
            api: api
        }
      end
    end

    solution[:path] = @path
    solution[:projects] = ret_projects
    solution[:test_projects] = ret_test_projects

    solution
  end

end
