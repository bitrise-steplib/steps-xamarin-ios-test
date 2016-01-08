# -----------------------
# --- Constants
# -----------------------

MONO_ANDROID_API_NAME = 'Mono.Android'
MONOTOUCH_API_NAME = 'monotouch'
XAMARIN_IOS_API_NAME = 'Xamarin.iOS'
XAMARIN_UITEST_API = 'Xamarin.UITest'

CSPROJ_EXT = '.csproj'
SHPROJ_EXT = '.shproj'
SLN_EXT = '.sln'

# -----------------------
# --- ProjectAnalyzer
# -----------------------

class ProjectAnalyzer

  def initialize(path)
    fail 'Empty path provided' if path.to_s == ''
    fail "File (#{path}) not exist" unless File.exist? path

    ext = File.extname(path)
    fail "Path (#{path}) is not a csproj path, extension should be: #{CSPROJ_EXT}" if ext != CSPROJ_EXT && ext != SHPROJ_EXT

    @path = path
  end

  def analyze(configuration, platform)
    id = parse_project_id

    output_path = parse_output_path(configuration, platform)

    api = parse_xamarin_api

    is_test = (api == XAMARIN_UITEST_API)

    build_ipa = false
    build_ipa = parse_allowed_to_build_ipa?(configuration, platform) if api == MONOTOUCH_API_NAME || api == XAMARIN_IOS_API_NAME

    sign_apk = false
    sign_apk = parse_allowed_to_sign_android?(configuration, platform) if api == MONO_ANDROID_API_NAME

    use_unsafe_blocks = parse_use_unsafe_blocks?

    {
        id: id,
        path: @path,
        configuration: configuration,
        platform: platform,
        api: api,
        output_path: output_path,
        is_test: is_test,
        build_ipa: build_ipa,
        sign_apk: sign_apk,
        use_unsafe_blocks: use_unsafe_blocks
    }
  end

  def parse_configs
    configs = []

    # <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|iPhoneSimulator' ">
    config_regexp = '<PropertyGroup Condition=" \'\$\(Configuration\)\|\$\(Platform\)\' == \'(?<config>.*)\' ">'

    File.open(@path).each do |line|
      match = line.match(config_regexp)

      next if match == nil || match.captures == nil || match.captures.count != 1

      configs << match.captures[0]
    end

    configs
  end

  def parse_solution_path
    # <ProjectTypeGuids>{FEACFBD2-3405-455C-9665-78FE426C6842};{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}</ProjectTypeGuids>
    project_ids_regexp = '<ProjectTypeGuids>(?<ids>.*)<\/ProjectTypeGuids>'

    solution_id = ''

    File.open(@path).each do |line|
      match = line.match(project_ids_regexp)

      next if match == nil || match.captures == nil || match.captures.count != 1
      ids = match.captures[0].split(';')

      prepared_ids = []
      ids.each do |id|
        id[0] = ''
        id[id.length-1] = ''

        prepared_ids << id
      end

      solution_id = prepared_ids.last
    end

    if solution_id
      solutions = Dir['**/*.sln']

      solutions.each do |solution|
        found_solution_id = SolutionAnalyzer.new(solution).parse_solution_id

        return solution if found_solution_id == solution_id
      end
    end

    nil
  end

  def parse_project_id
    # <ProjectGuid>{90F3C584-FD69-4926-9903-6B9771847782}</ProjectGuid>
    project_id_regexp = '<ProjectGuid>{(?<id>.*)<\/ProjectGuid>'

    File.open(@path).each do |line|
      match = line.match(project_id_regexp)

      return match.captures[0] if match && match.captures && match.captures.count == 1
    end

    nil
  end

  def parse_referred_project_ids
    ids = []

    # <ProjectReference Include="..\CreditCardValidator.Droid\CreditCardValidator.Droid.csproj">
    project_reference_start_regexp = '<ProjectReference Include="(?<project>.*)">'
    project_reference_end_regexp = '<\/ProjectReference>'
    project_reference_start = false

    # <Project>{90F3C584-FD69-4926-9903-6B9771847782}</Project>
    project_regexp = '<Project>{(?<id>.*)<\/Project>'

    File.open(@path).each do |line|
      match = line.match(project_reference_start_regexp)
      if match && match.captures && match.captures.count == 1
        project_reference_start = true
        next
      end

      match = line.match(project_reference_end_regexp)
      if match
        project_reference_start = false
        next
      end

      if project_reference_start
        match = line.match(project_regexp)
        if match && match.captures && match.captures.count == 1
          id = match.captures[0]
          ids << id
          next
        end
      end
    end

    ids
  end

  def parse_output_path(configuration, platform)
    # <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|iPhone' ">
    config_regexp = '<PropertyGroup Condition=" \'\$\(Configuration\)\|\$\(Platform\)\' == \'(?<config>.*)\' ">'

    # <OutputPath>bin\Debug</OutputPath>
    output_path_regexp = '<OutputPath>(?<path>.*)<\/OutputPath>'

    related_config_start = false

    config = configuration + '|' + platform

    File.open(@path).each do |line|
      match = line.match(config_regexp)
      if match && match.captures && match.captures.count == 1
        found_config = match.captures[0]

        related_config_start = (found_config == config)
      end

      next unless related_config_start

      match = line.match(output_path_regexp)
      if match && match.captures && match.captures.count == 1
        output_path = match.captures[0].strip
        output_path = output_path.gsub(/\\/, '/')

        dirty = true
        while dirty do
          output_path[output_path.length-1] = '' if output_path[output_path.length-1] == '/'
          dirty = false if output_path[output_path.length-1] != '/'
        end

        return output_path
      end
    end

    nil
  end

  def parse_use_unsafe_blocks?
    # <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
    if File.file?(@path)
      lines = File.readlines(@path)

      return true if lines.grep(/<AllowUnsafeBlocks>true<\/AllowUnsafeBlocks>/).size > 0
    end

    false
  end

  def parse_allowed_to_build_ipa?(configuration, platform)
    # <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|iPhone' ">
    config_regexp = '<PropertyGroup Condition=" \'\$\(Configuration\)\|\$\(Platform\)\' == \'(?<config>.*)\' ">'

    related_config_start = false

    config = configuration + '|' + platform

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

  def parse_allowed_to_sign_android?(configuration, platform)
    # <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|AnyCPU' ">
    config_regexp = '<PropertyGroup Condition=" \'\$\(Configuration\)\|\$\(Platform\)\' == \'(?<config>.*)\' ">'
    config = configuration + '|' + platform
    related_config_start = false

    File.open(@path).each do |line|
      match = line.match(config_regexp)
      if match && match.captures && match.captures.count == 1
        found_config = match.captures[0]

        related_config_start = true if config == found_config
      end

      next unless related_config_start

      return true if line.downcase.include? '<androidkeystore>true</androidkeystore>'
    end

    false
  end

  def parse_xamarin_api
    if File.file?(@path)
      lines = File.readlines(@path)

      return MONO_ANDROID_API_NAME if lines.grep(/Include="Mono.Android"/).size > 0
      return MONOTOUCH_API_NAME if lines.grep(/Include="monotouch"/).size > 0
      return XAMARIN_IOS_API_NAME if lines.grep(/Include="Xamarin.iOS"/).size > 0
      return XAMARIN_UITEST_API if lines.grep(/Include="Xamarin.UITest"/).size > 0
    end

    nil
  end

end

# -----------------------
# --- SolutionAnalyzer
# -----------------------

class SolutionAnalyzer

  def initialize(path)
    fail 'Empty path provided' if path.to_s == ''
    fail "File (#{path}) not exist" unless File.exist? path

    ext = File.extname(path)
    fail "Path (#{path}) is not a solution path, extension should be: #{SLN_EXT}" if ext != SLN_EXT

    @path = path
  end

  def analyze
    projects = parse_projects
    solution_configs = parse_solution_configs
    project_configs = parse_project_configs

    solution_id = ''
    ret_projects = []
    ret_test_projects = []

    projects.each do |project|
      project_config = project_configs[project[:id]]

      next unless project_config

      solution_id = project[:solution_id]

      ext = File.extname(project[:path])
      if ext != CSPROJ_EXT && ext != SHPROJ_EXT
        puts
        puts "Project file (#{project[:path]}) with unknown extension, skip parsing..."
        next
      end

      api = ProjectAnalyzer.new(project[:path]).parse_xamarin_api

      next unless api

      ret_project = {
          id: project[:id],
          path: project[:path],
          solution_id: project[:solution_id],
          api: api,
          mapping: project_config
      }

      # FIX
      # any cpu platform in solution contains space sometimes,
      # that prevents to select proper configuration-platform in project
      mapping = fixed_mapping(ret_project)
      ret_project[:mapping] = mapping

      ret_test_projects << ret_project if api == XAMARIN_UITEST_API
      ret_projects << ret_project unless api == XAMARIN_UITEST_API
    end

    {
        id: solution_id,
        path: @path,
        configs: solution_configs,
        projects: ret_projects,
        test_projects: ret_test_projects
    }
  end

  def parse_solution_id
    # Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "CreditCardValidator", "CreditCardValidator\CreditCardValidator.csproj", "{99A825A6-6F99-4B94-9F65-E908A6347F1E}"
    p_regexp = 'Project\("{(?<solution_id>.*)}"\) = "(?<project_name>.*)", "(?<project_path>.*)", "{(?<project_id>.*)}"'

    File.open(@path).each do |line|
      match = line.match(p_regexp)

      return match.captures[0] if match && match.captures && match.captures.count == 4
    end
  end

  def collect_projects(configuration, platform)
    projects_to_build = []

    solution = SolutionAnalyzer.new(@path).analyze
    solution[:projects].each do |project|
      mapping = project[:mapping]
      config = mapping["#{configuration}|#{platform}"]
      fail "No mapping found for config: #{configuration}|#{platform}" unless config

      mapped_configuration, mapped_platform = config.split('|')
      fail "No configuration, platform found for config: #{config}" unless configuration || platform

      parsed_project = ProjectAnalyzer.new(project[:path]).analyze(mapped_configuration, mapped_platform)

      projects_to_build << parsed_project
    end

    projects_to_build
  end

  def collect_test_projects(configuration, platform)
    projects_to_build = []

    solution = SolutionAnalyzer.new(@path).analyze
    solution[:test_projects].each do |project|
      mapping = project[:mapping]
      config = mapping["#{configuration}|#{platform}"]
      fail "No mapping found for config: #{configuration}|#{platform}" unless config

      mapped_configuration, mapped_platform = config.split('|')
      fail "No configuration, platform found for config: #{config}" unless configuration || platform

      parsed_project = ProjectAnalyzer.new(project[:path]).analyze(mapped_configuration, mapped_platform)

      projects_to_build << parsed_project
    end

    projects_to_build
  end

  private

  def platform_any_cpu?(platform)
    downcase_platform = platform.downcase
    return true if downcase_platform == 'anycpu' || downcase_platform == 'any cpu'
    false
  end

  def fixed_mapping(project)
    fixed_mapping = {}

    project_configs = ProjectAnalyzer.new(project[:path]).parse_configs

    project[:mapping].each do |s_config, p_config|
      project_configs.each do |project_config|
        project_config_in_solution = p_config
        project_config_in_project = project_config

        configuration_in_solution, platform_in_solution = project_config_in_solution.split('|')
        configuration_in_project, platform_in_project = project_config_in_project.split('|')

        next unless configuration_in_solution == configuration_in_project

        if platform_in_solution == platform_in_project
          fixed_project_config = configuration_in_project + '|' + platform_in_project
          fixed_mapping[s_config] = fixed_project_config
        elsif platform_any_cpu?(platform_in_solution) && platform_any_cpu?(platform_in_project)
          fixed_project_config = configuration_in_project + '|' + platform_in_project
          fixed_mapping[s_config] = fixed_project_config
        end
      end
    end

    fixed_mapping
  end

  def parse_projects
    projects = []

    # Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "CreditCardValidator", "CreditCardValidator\CreditCardValidator.csproj", "{99A825A6-6F99-4B94-9F65-E908A6347F1E}"
    p_regexp = 'Project\("{(?<solution_id>.*)}"\) = "(?<project_name>.*)", "(?<project_path>.*)", "{(?<project_id>.*)}"'

    File.open(@path).each do |line|
      match = line.match(p_regexp)

      next if match == nil || match.captures == nil || match.captures.count != 4

      solution_id = match.captures[0]
      # project_name = match.captures[1]
      project_path = match.captures[2].strip.gsub(/\\/, '/')
      project_id = match.captures[3]

      project_path = File.expand_path(project_path, File.dirname(@path))
      next unless File.exist? project_path

      projects << {
          :solution_id => solution_id,
          :path => project_path,
          :id => project_id
      }
    end

    projects
  end

  def parse_solution_configs
    solution_configs = []

    s_configs_start = 'GlobalSection(SolutionConfigurationPlatforms) = preSolution'
    s_configs_end = 'EndGlobalSection'
    is_next_s_config = false

    File.open(@path).each do |line|

      if line.include?(s_configs_start)
        is_next_s_config = true
        next
      end

      if line.include?(s_configs_end)
        is_next_s_config = false
        next
      end

      next unless is_next_s_config

      config = line.split('=')[1].strip!
      solution_configs << config

    end

    solution_configs
  end

  def parse_project_configs
    project_configs = {}

    is_next_p_config = false
    p_configs_start = 'GlobalSection(ProjectConfigurationPlatforms) = postSolution'
    p_configs_end = 'EndGlobalSection'
    p_config_regexp = '{(?<project_id>.*)}.(?<solution_configuration_platform>.*|.*) = (?<project_configuration_platform>.*)'

    File.open(@path).each do |line|
      if line.include?(p_configs_start)
        is_next_p_config = true
        next
      end

      if line.include?(p_configs_end)
        is_next_p_config = false
        next
      end

      next unless is_next_p_config

      match = line.match(p_config_regexp)

      next if match == nil || match.captures == nil || match.captures.count != 3

      project_id = match.captures[0]

      s_config = match.captures[1].strip
      s_config = s_config.split('.')[0] if s_config.include? '.'

      p_config = match.captures[2].strip

      project_configs[project_id] = {} unless project_configs[project_id]
      project_configs[project_id][s_config] = p_config
    end

    project_configs
  end

end
