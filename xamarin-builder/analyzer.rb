require 'time'
require 'pathname'

require_relative 'common_constants'

# -----------------------
# --- Constants
# -----------------------

MDTOOL_PATH = "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\""

CSPROJ_EXT = '.csproj'
FSPROJ_EXT = '.fsproj'
SHPROJ_EXT = '.shproj'
SLN_EXT = '.sln'

SOLUTION = 'solution'
PROJECT = 'project'

#
# Solution regex
REGEX_SOLUTION_PROJECTS = /Project\(\"(?<solution_id>[^\"]*)\"\) = \"(?<project_name>[^\"]*)\", \"(?<project_path>[^\"]*)\", \"(?<project_id>[^\"]*)\"/i
REGEX_SOLUTION_GLOBAL_SOLUTION_CONFIG_START = /GlobalSection\(SolutionConfigurationPlatforms\) = preSolution/i
REGEX_SOLUTION_GLOBAL_SOLUTION_CONFIG = /^\s*(?<config>[^|]*)\|(?<platform>[^|]*) =/i
REGEX_SOLUTION_GLOBAL_PROJECT_CONFIG_START = /GlobalSection\(ProjectConfigurationPlatforms\) = postSolution/i
REGEX_SOLUTION_GLOBAL_PROJECT_CONFIG = /(?<project_id>{[^}]*}).(?<config>.*)\|(?<platform>.*)\.Build.* = (?<mapped_config>.*)\|(?<mapped_platform>(.)*)/i
REGEX_SOLUTION_GLOBAL_CONFIG_END = /EndGlobalSection/i

#
# Project regex
REGEX_PROJECT_TARGET_DEFINITION = /import project=\"(?<target_definition>.*\.targets)\"/i
REGEX_PROJECT_GUID = /<ProjectGuid>(?<project_id>.*)<\/ProjectGuid>/i
REGEX_PROJECT_TYPE_GUIDS = /<ProjectTypeGuids>(?<project_type_guids>.*)<\/ProjectTypeGuids>/i
REGEX_PROJECT_OUTPUT_TYPE = /<OutputType>(?<output_type>.*)<\/OutputType>/i
REGEX_PROJECT_ASSEMBLY_NAME = /<AssemblyName>(?<assembly_name>.*)<\/AssemblyName>/i

REGEX_PROJECT_PROPERTY_GROUP = /<PropertyGroup>/i
REGEX_PROJECT_PROPERTY_GROUP_WITH_CONDITION_WITH_CONFIGURATION_AND_PLATFORM = /<PropertyGroup Condition=\"\s*'\$\(Configuration\)\|\$\(Platform\)'\s*==\s*'(?<config>.*)\|(?<platform>.*)'\s*\">/i
REGEX_PROJECT_PROPERTY_GROUP_WITH_CONDITION_WITH_CONFIGURATION = /<PropertyGroup Condition=\"\s*'\$\(Configuration\)'\s*==\s*'(?<config>.*)'\s*\">/i
REGEX_PROJECT_PROPERTY_GROUP_WITH_CONDITION_WITH_PLATFORM= /<PropertyGroup Condition=\"\s*'\$\(Platform\)'\s*==\s*'(?<platform>.*)'\s*\">/i
REGEX_PROJECT_PROPERTY_GROUP_END = /<\/PropertyGroup>/i

REGEX_PROJECT_OUTPUT_PATH = /<OutputPath>(?<output_path>.*)<\/OutputPath>/i
REGEX_PROJECT_PROJECT_REFERENCE_START = /<ProjectReference Include="(?<project_path>.*)">/i
REGEX_PROJECT_PROJECT_REFERENCE_END = /<\/ProjectReference>/i
REGEX_PROJECT_REFERRED_PROJECT_ID = /<Project>(?<id>.*)<\/Project>/i

#
# Xamarin.iOS specific regex
REGEX_PROJECT_IPA_PACKAGE = /<IpaPackageName>/i
REGEX_PROJECT_BUILD_IPA = /<BuildIpa>True<\/BuildIpa>/i
REGEX_PROJECT_MTOUCH_ARCH = /<MtouchArch>(?<arch>.*)<\/MtouchArch>/i

#
# Xamarin.Android specific regex
REGEX_PROJECT_ANDROID_MANIFEST = /<AndroidManifest>(?<manifest_path>.*)<\/AndroidManifest>/i
REGEX_PROJECT_ANDROID_PACKAGE_NAME = /<manifest.*package=\"(?<package_name>.*)\">/i
REGEX_PROJECT_ANDROID_APPLICATION= /<AndroidApplication>True<\/AndroidApplication>/i
REGEX_PROJECT_SIGN_ANDROID = /<AndroidKeyStore>True<\/AndroidKeyStore>/i

#
# Assembly references
# <Reference Include="Xamarin.UITest">
REGEX_PROJECT_REFERENCE_XAMARIN_UITEST = /Include="Xamarin.UITest/i
# <Reference Include="nunit.framework, Version=2.6.4.14350, Culture=neutral, PublicKeyToken=96d09a1eb7f44a77, processorArchitecture=MSIL">
REGEX_PROJECT_REFERENCE_NUNIT_FRAMEWORK = /Include="nunit.framework/i
# <Reference Include="MonoTouch.NUnitLite" />
REGEX_PROJECT_REFERENCE_NUNIT_LITE_FRAMEWORK = /Include="MonoTouch.NUnitLite/i

REGEX_ARCHIVE_DATE_TIME = /\s(.*[AM]|[PM]).*\./i

class Analyzer
  # references:
  # https://github.com/mono/monodevelop/blob/master/main/src/core/MonoDevelop.Core/MonoDevelop.Core.addin.xml#L299
  @project_type_guid_map = {
    'Xamarin.iOS' => [
      'E613F3A2-FE9C-494F-B74E-F63BCB86FEA6',
      '6BC8ED88-2882-458C-8E55-DFD12B67127B',
      'F5B4F3BC-B597-4E2B-B552-EF5D8A32436F',
      'FEACFBD2-3405-455C-9665-78FE426C6842',
      '8FFB629D-F513-41CE-95D2-7ECE97B6EEEC',
      'EE2C853D-36AF-4FDB-B1AD-8E90477E2198'
    ],
    'Xamarin.Android' => [
      'EFBA0AD7-5A72-4C68-AF49-83D382785DCF',
      '10368E6C-D01B-4462-8E8B-01FC667A7035'
    ],
    'MonoMac' => [
      '1C533B1C-72DD-4CB1-9F6B-BF11D93BCFBE',
      '948B3504-5B70-4649-8FE4-BDE1FB46EC69'
    ],
    'Xamarin.Mac' => [
      '42C0BBD9-55CE-4FC1-8D90-A7348ABAFB23',
      'A3F8F2AB-B479-4A4A-A458-A89E7DC349F1'
    ],
    'Xamarin.tvOS' => [
      '06FA79CB-D6CD-4721-BB4B-1BD202089C55'
    ]
  }

  class << self
    attr_accessor :project_type_guid_map
  end

  def analyze(path)
    @path = path

    case type
    when SOLUTION
      analyze_solution(@path)
    when PROJECT
      puts
      puts "\e[32mYou are trying to build a project file at path #{@path}\e[0m"
      puts "You should specify the solution path and set the type of the project you would like to build: [iOS|Android|Mac]"
      puts
      raise "Unsupported type detected"
    end

    @solution[:projects].each do |project|
      analyze_project(project)
    end
  end

  def inspect
    puts "-- analyze: #{@path}"
    puts
    puts @solution
  end

  def build_solution_command(config, platform)
    mdtool_build_command('build', [config, platform].join('|'), @solution[:path])
  end

  def build_commands(config, platform, project_type_filter, id_filters = nil)
    configuration = "#{config}|#{platform}"
    build_commands = []

    @solution[:projects].each do |project|
      next unless project[:mappings]
      project_configuration = project[:mappings][configuration]

      unless id_filters.nil?
        next unless id_filters.include? project[:id]
      end

      case project[:api]
        when Api::IOS, Api::TVOS
          next unless project_type_filter.any? { |api| [Api::IOS, Api::TVOS].include? api }
          next unless project[:output_type].eql?('exe')
          next unless project_configuration

          generate_archive = should_generate_archives?(project[:configs][project_configuration][:mtouch_arch])

          build_commands << mdtool_build_command('build', project_configuration, @solution[:path], project[:name])
          build_commands << mdtool_build_command('archive', project_configuration, @solution[:path], project[:name]) if generate_archive
        when Api::MAC
          next unless project_type_filter.include? Api::MAC
          next unless project[:output_type].eql?('exe')
          next unless project_configuration

          build_commands << mdtool_build_command('build', project_configuration, @solution[:path], project[:name])
          build_commands << mdtool_build_command('archive', project_configuration, @solution[:path], project[:name])
        when Api::ANDROID
          next unless project_type_filter.include? Api::ANDROID
          next unless project[:android_application]
          next unless project_configuration

          project_config, project_platform = project_configuration.split('|')
          sign_android = project[:configs][project_configuration][:sign_android]

          build_command = [
              'xbuild',
              sign_android ? '/t:SignAndroidPackage' : '/t:PackageForAndroid',
              "/p:Configuration=\"#{project_config}\""
          ]
          build_command << "/p:Platform=\"#{project_platform}\"" unless project_platform.eql?("AnyCPU")
          build_command << "\"#{project[:path]}\""
          build_command << "/verbosity:minimal"
          build_command << "/nologo"

          build_commands << build_command
        else
          next
      end
    end

    build_commands
  end

  def build_test_commands(config, platform, project_type_filter)
    configuration = "#{config}|#{platform}"
    build_commands = []
    errors = []

    @solution[:projects].each do |project|
      # Check whether it is a UITest project
      # Do this check as soon as possible,
      # to allow collecting errors of building test command
      # for relevant (UITest) projects.
      next if project[:tests].nil? || !project[:tests].include?(Tests::UITEST)

      test_project = project[:name]

      unless project[:mappings]
        errors << "#{test_project} not found in solution mappings"
        errors << project.to_s
        next
      end

      project_configuration = project[:mappings][configuration]
      unless project_configuration
        errors << "no mapping found for #{test_project} with #{configuration}"
        errors << project.to_s
        next
      end

      # Checked referenced projects if it includes
      # the correct project type [iOS|Android]
      referred_projects = []

      unless project[:referred_project_ids]
        errors << "no referred projects found for #{test_project}"
        errors << project.to_s
        next
      end

      project[:referred_project_ids].each do |id|
        referred_project = project_with_id(id)

        unless referred_project
          errors << "project reference exist with project id: #{id}, but project not found in solution"
          errors << project.to_s
          next
        end

        unless referred_project[:api]
          errors << "no api found for referred project: #{referred_project}"
          errors << project.to_s
          next
        end

        referred_projects << referred_project if project_type_filter.include? referred_project[:api]
      end

      if referred_projects.empty?
        errors << "#{test_project} does not refer to any #{project_type_filter} projects"
        errors << project.to_s
        next
      end

      referred_projects.each do |referred_project|
        command = build_commands(config, platform, project_type_filter, referred_project[:id])
        build_commands.concat(command) unless command.nil?
      end

      build_commands << mdtool_build_command('build', project_configuration, @solution[:path], project[:name])
    end

    [build_commands, errors]
  end

  def nunit_light_test_commands(config, platform, touch_unit_server, logfile)
    configuration = "#{config}|#{platform}"
    build_commands = []
    errors = []

    raise "Touch.Server.exe not found at path: #{touch_unit_server}" unless File.exists?(touch_unit_server)

    @solution[:projects].each do |project|
      next if project[:tests].nil? || !project[:tests].include?(Tests::NUNIT_LITE)

      test_project = project[:name]

      unless project[:mappings]
        errors << "#{test_project} not found in solution mappings"
        errors << project.to_s
        next
      end

      project_configuration = project[:mappings][configuration]
      unless project_configuration
        errors << "no mapping found for #{test_project} with #{configuration}"
        errors << project.to_s
        next
      end

      project_config = project_configuration.split('|').first
      unless project_config
        errors << "#{test_project} configuration #{project_configuration} is invalid"
        errors << project.to_s
        next
      end

      build_commands << mdtool_build_command('build', project_configuration, @solution[:path], project[:name])

      command = [
          "mono --debug",
          "\"#{touch_unit_server}\"",
          "--launchsim",
          "-autoexit",
          "-logfile=#{logfile}"
      ]

      build_commands << command
    end

    [build_commands, errors]
  end

  def nunit_test_commands(config, platform, options)
    configuration = "#{config}|#{platform}"
    build_commands = []
    errors = []

    nunit_path = ENV['NUNIT_PATH']
    nunit_console_path = File.join(nunit_path, 'nunit3-console.exe')
    raise "nunit3-console.exe not found at path: #{nunit_console_path}" unless File.exists?(nunit_console_path)

    @solution[:projects].each do |project|
      # Check whether it is a Nunit project
      # Do this check as soon as possible,
      # to allow collecting errors of building test command
      # for relevant (Nunit) projects.
      next if project[:tests].nil? || !project[:tests].include?(Tests::NUNIT) || project[:tests].include?(Tests::UITEST)

      test_project = project[:name]

      unless project[:mappings]
        errors << "#{test_project} not found in solution mappings"
        errors << project.to_s
        next
      end

      project_configuration = project[:mappings][configuration]
      unless project_configuration
        errors << "no mapping found for #{test_project} with #{configuration}"
        errors << project.to_s
        next
      end

      project_config = project_configuration.split('|').first
      unless project_config
        errors << "#{test_project} configuration #{project_configuration} is invalid"
        errors << project.to_s
        next
      end

      command = [
          "mono",
          "\"#{nunit_console_path}\"",
          "\"#{project[:path]}\"",
          "\"/config:#{project_config}\""
      ]
      command << options unless options.nil?
      build_commands << command
    end

    [build_commands, errors]
  end

  def collect_generated_files(config, platform, project_type_filter)
    outputs_hash = {}

    configuration = "#{config}|#{platform}"

    @solution[:projects].each do |project|
      next unless project[:mappings]
      project_configuration = project[:mappings][configuration]

      case project[:api]
      when Api::IOS, Api::TVOS
        next unless project_type_filter.any? { |api| [Api::IOS, Api::TVOS].include? api }
        next unless project[:output_type].eql?('exe')
        next unless project_configuration

        generate_archive = should_generate_archives?(project[:configs][project_configuration][:mtouch_arch])

        project_path = project[:path]
        project_dir = File.dirname(project_path)
        rel_output_dir = project[:configs][project_configuration][:output_path]
        full_output_dir = File.join(project_dir, rel_output_dir)

        outputs_hash[project[:id]] = {}
        if generate_archive
          full_output_path = latest_archive_path(project[:name])

          outputs_hash[project[:id]][:xcarchive] = full_output_path if full_output_path
        else
          full_output_path = export_artifact(project[:assembly_name], full_output_dir, '.app')

          outputs_hash[project[:id]][:app] = full_output_path if full_output_path
        end

        outputs_hash[project[:id]][:api] = project[:api]
      when Api::MAC
        next unless project_type_filter.include? Api::MAC
        next unless project[:output_type].eql?('exe')
        next unless project_configuration

        outputs_hash[project[:id]] = {}
        full_output_path = latest_archive_path(project[:name])

        outputs_hash[project[:id]][:xcarchive] = full_output_path if full_output_path
        outputs_hash[project[:id]][:api] = project[:api]
      when Api::ANDROID
        next unless project_type_filter.include? Api::ANDROID
        next unless project[:android_application]
        next unless project_configuration

        project_path = project[:path]
        project_dir = File.dirname(project_path)
        rel_output_dir = project[:configs][project_configuration][:output_path]
        full_output_dir = File.join(project_dir, rel_output_dir)

        package_name = project[:android_manifest_path].nil? ? '*' : android_package_name(project[:android_manifest_path])
        sign_android = project[:configs][project_configuration][:sign_android]

        full_output_path = nil

        if sign_android
          pattern = File.join(full_output_dir, "#{package_name}*signed.apk")
          artifact_path = Dir.glob(pattern, File::FNM_CASEFOLD).first if package_name
          full_output_path = artifact_path if !artifact_path.nil? && File.exist?(artifact_path)

          pattern = File.join(full_output_dir, '*signed.apk')
          artifact_path = Dir.glob(pattern, File::FNM_CASEFOLD).first
          full_output_path = artifact_path if full_output_path.nil? && !artifact_path.nil? && File.exist?(artifact_path)
        elsif package_name
          full_output_path = export_artifact(package_name, full_output_dir, '.apk')
        end
 
        full_output_path = export_artifact('*', full_output_dir, '.apk') unless full_output_path

        outputs_hash[project[:id]] = {}
        outputs_hash[project[:id]][:apk] = full_output_path if full_output_path
        outputs_hash[project[:id]][:api] = project[:api]
      else
        next
      end

      # Search for test dll
      next unless project[:uitest_projects]

      project[:uitest_projects].each do |test_project_id|
        test_project = project_with_id(test_project_id)
        next unless test_project

        test_project_configuration = test_project[:mappings][configuration]
        next unless test_project_configuration
        next unless test_project[:configs][test_project_configuration]

        test_project_path = test_project[:path]
        test_project_dir = File.dirname(test_project_path)
        test_rel_output_dir = test_project[:configs][test_project_configuration][:output_path]
        test_full_output_dir = File.join(test_project_dir, test_rel_output_dir)

        test_full_output_path = export_artifact(test_project[:assembly_name], test_full_output_dir, '.dll')

        (outputs_hash[project[:id]][:uitests] ||= []) << test_full_output_path if test_full_output_path
      end
    end

    outputs_hash
  end

  def ios_project_type?(guid)
    ios_guids = Analyzer.project_type_guid_map['Xamarin.iOS']
    ios_guids.include? guid
  end

  def android_project_type?(guid)
    android_guids = Analyzer.project_type_guid_map['Xamarin.Android']
    android_guids.include? guid
  end

  def mac_project_type?(guid)
    mac_guids = Analyzer.project_type_guid_map['MonoMac'].concat Analyzer.project_type_guid_map['Xamarin.Mac']
    mac_guids.include? guid
  end

  def tv_project_type?(guid)
    tv_guids = Analyzer.project_type_guid_map['Xamarin.tvOS']
    tv_guids.include? guid
  end

  def identify_project_api(project_type_guids_str)
    project_type_guids = project_type_guids_str.split(';')

    project_type_guids.each do |project_type_guid|
      project_type_guid = project_type_guid.strip
      project_type_guid = project_type_guid.tr('{', '')
      project_type_guid = project_type_guid.tr('}', '')

      return Api::IOS if ios_project_type?(project_type_guid)
      return Api::ANDROID if android_project_type?(project_type_guid)
      return Api::MAC if mac_project_type?(project_type_guid)
      return Api::TVOS if tv_project_type?(project_type_guid)
    end

    Api::UNKNOWN
  end

  private

  def android_package_name(manifest_path)
    File.open(manifest_path).each do |line|
      match = line.match(REGEX_PROJECT_ANDROID_PACKAGE_NAME)
      if match != nil && match.captures != nil && match.captures.count == 1
        return match.captures[0]
      end
    end

    nil
  end

  def type
    return SOLUTION if @path.downcase.end_with? SLN_EXT
    return PROJECT if @path.downcase.end_with? CSPROJ_EXT or @path.downcase.end_with? FSPROJ_EXT
    raise "unsupported type for path: #{@path}"
  end

  def analyze_solution(solution_path)
    @solution = {
        path: solution_path,
        base_dir: File.dirname(@path)
    }

    parse_solution_configs = false
    parse_project_configs = false

    File.open(@solution[:path]).each do |line|
      # Project
      match = line.match(REGEX_SOLUTION_PROJECTS)
      if match != nil && match.captures != nil && match.captures.count == 4
        # Skip files that are directories or doesn't exist
        project_path = File.join([@solution[:base_dir]].concat(match.captures[2].split('\\')))

        if File.file? project_path
          @solution[:id] = match.captures[0]
          (@solution[:projects] ||= []) << {
              name: match.captures[1],
              path: project_path,
              id: match.captures[3],
          }
        end
      end

      # Solution configs
      match = line.match(REGEX_SOLUTION_GLOBAL_CONFIG_END)
      parse_solution_configs = false if match != nil

      if parse_solution_configs
        match = line.match(REGEX_SOLUTION_GLOBAL_SOLUTION_CONFIG)
        if match != nil && match.captures != nil && match.captures.count == 2
          configuration =  match.captures[0].strip
          platform = match.captures[1].strip
          (@solution[:configs] ||= []) << "#{configuration}|#{platform}"
        end
      end

      match = line.match(REGEX_SOLUTION_GLOBAL_SOLUTION_CONFIG_START)
      parse_solution_configs = true if match != nil

      # Project configs
      match = line.match(REGEX_SOLUTION_GLOBAL_CONFIG_END)
      parse_project_configs = false if match != nil

      if parse_project_configs
        match = line.match(REGEX_SOLUTION_GLOBAL_PROJECT_CONFIG)
        if match != nil && match.captures != nil && match.captures.count == 5
          project_id = match.captures[0]
          solution_configuration = match.captures[1].strip
          solution_platform = match.captures[2].strip
          project_configuration = match.captures[3].strip
          project_platform = match.captures[4].strip
          project_platform = 'AnyCPU' if project_platform.eql? 'Any CPU' # Fix MS bug

          project = project_with_id(project_id)
          next unless project

          (project[:mappings] ||= {})["#{solution_configuration}|#{solution_platform}"] = "#{project_configuration}|#{project_platform}"
          (project[:configs] ||= {})["#{project_configuration}|#{project_platform}"] = {}
        end
      end

      match = line.match(REGEX_SOLUTION_GLOBAL_PROJECT_CONFIG_START)
      parse_project_configs = true if match != nil
    end

    # Remove projects without any mapping or config
    valid_projects = []
    @solution[:projects].each do |project|
      has_mapping = (project[:mappings] && project[:mappings].length)
      has_config = (project[:configs] && project[:configs].length)

      puts "project #{project} is referred in solution, but does not contains any mapping" unless has_mapping
      puts "project #{project} is referred in solution, but does not contains any config" unless has_config

      valid_projects << project if has_mapping && has_config
    end

    @solution[:projects] = valid_projects
  end

  def analyze_project(project)
    file = File.open(project[:path])
    analyze_project_definition(project, file)
  end

  def analyze_project_definition(project, file)
    project_configs = []
    referred_project_paths = nil

    file.each do |line|
      # Target definition
      match = line.match(REGEX_PROJECT_TARGET_DEFINITION)
      if match != nil && match.captures != nil && match.captures.count == 1
        relative_path = match.captures[0]

        unless relative_path.include? "$(MSBuild"
          project_dir = File.dirname(project[:path])
          definition_path = File.expand_path(File.join([project_dir].concat(match.captures[0].split('\\'))))

          if File.exist?(definition_path)
            definition_file = File.open(definition_path)
            analyze_project_definition(project, definition_file)
          end
        end
      end

      # Guid
      match = line.match(REGEX_PROJECT_GUID)
      if match != nil && match.captures != nil && match.captures.count == 1
        if project[:id].casecmp(match.captures[0]) != 0
          next
        end
      end

      # Project type guid
      match = line.match(REGEX_PROJECT_TYPE_GUIDS)
      if match != nil && match.captures != nil && match.captures.count == 1
        project[:project_type_guids] = match.captures[0]
      end

      # output type
      match = line.match(REGEX_PROJECT_OUTPUT_TYPE)
      if match != nil && match.captures != nil && match.captures.count == 1
        project[:output_type] = match.captures[0].downcase
      end

      # assembly name
      match = line.match(REGEX_PROJECT_ASSEMBLY_NAME)
      if match != nil && match.captures != nil && match.captures.count == 1
        project[:assembly_name] = match.captures[0]
      end

      # manifest path
      match = line.match(REGEX_PROJECT_ANDROID_MANIFEST)
      if match != nil && match.captures != nil && match.captures.count == 1
        project_dir = File.dirname(project[:path])
        project[:android_manifest_path] = File.join([project_dir].concat(match.captures[0].split('\\')))
      end

      # android application
      match = line.match(REGEX_PROJECT_ANDROID_APPLICATION)
      if match != nil
        project[:android_application] = true
      end

      # PropertyGroup with condition
      match = line.match(REGEX_PROJECT_PROPERTY_GROUP_END)
      project_configs = [] if match

      unless project_configs.empty?
        match = line.match(REGEX_PROJECT_OUTPUT_PATH)
        if match != nil && match.captures != nil && match.captures.count == 1
          project_configs.each do |project_config|
            configuration, platform = project_config.split('|')
            output_path = match.captures[0]
            output_path.sub!("$(Configuration)", configuration)
            output_path.sub!("$(Platform)", platform)

            project[:configs][project_config][:output_path] = File.join(output_path.split('\\'))
          end
        end

        match = line.match(REGEX_PROJECT_MTOUCH_ARCH)
        if match != nil && match.captures != nil && match.captures.count == 1
          project_configs.each do |project_config|
            project[:configs][project_config][:mtouch_arch] = match.captures[0].split(',').collect { |x| x.strip || x }
          end
        end

        match = line.match(REGEX_PROJECT_SIGN_ANDROID)
        if match != nil
          project_configs.each do |project_config|
            project[:configs][project_config][:sign_android] = true
          end
        end

        match = line.match(REGEX_PROJECT_IPA_PACKAGE)
        if match != nil
          project_configs.each do |project_config|
            project[:configs][project_config][:ipa_package] = true
          end
        end

        match = line.match(REGEX_PROJECT_BUILD_IPA)
        if match != nil
          project_configs.each do |project_config|
            project[:configs][project_config][:build_ipa] = true if match != nil
          end
        end
      end

      match = line.match(REGEX_PROJECT_PROPERTY_GROUP)
      if match != nil && project[:configs] != nil
        project_configs = []
        project[:configs].each do |project_config,value|
          project[:configs][project_config] ||= {}
          project_configs << project_config
        end
      end

      match = line.match(REGEX_PROJECT_PROPERTY_GROUP_WITH_CONDITION_WITH_CONFIGURATION_AND_PLATFORM)
      if match != nil && match.captures != nil && match.captures.count == 2
        configuration = match.captures[0].strip
        platform = match.captures[1].strip
        project_config = "#{configuration}|#{platform}"

        project[:configs][project_config] ||= {}
        project_configs = [project_config]
      end

      match = line.match(REGEX_PROJECT_PROPERTY_GROUP_WITH_CONDITION_WITH_CONFIGURATION)
      if match != nil && match.captures != nil && match.captures.count == 1
        configuration = match.captures[0].strip
        project_config_filter = "#{configuration}|"

        project_configs = []
        project[:configs].each do |project_config,value|
          project[:configs][project_config] ||= {}
          project_configs << project_config if project_config.include?(project_config_filter)
        end
      end

      match = line.match(REGEX_PROJECT_PROPERTY_GROUP_WITH_CONDITION_WITH_PLATFORM)
      if match != nil && match.captures != nil && match.captures.count == 1
        platform = match.captures[0].strip
        project_config_filter = "|#{platform}"

        project_configs = []
        project[:configs].each do |project_config,value|
          project[:configs][project_config] ||= {}
          project_configs << project_config if project_config.include?(project_config_filter)
        end
      end

      # API
      match = line.match(REGEX_PROJECT_TYPE_GUIDS)
      project[:api] = identify_project_api(match.captures.first) if match != nil && match.captures != nil && match.captures.count == 1

      match = line.match(REGEX_PROJECT_REFERENCE_XAMARIN_UITEST)
      (project[:tests] ||= []) << Tests::UITEST if match != nil

      match = line.match(REGEX_PROJECT_REFERENCE_NUNIT_FRAMEWORK)
      (project[:tests] ||= []) << Tests::NUNIT if match != nil

      match = line.match(REGEX_PROJECT_REFERENCE_NUNIT_LITE_FRAMEWORK)
      (project[:tests] ||= []) << Tests::NUNIT_LITE if match != nil

      # Referred projects
      match = line.match(REGEX_PROJECT_PROJECT_REFERENCE_END)
      referred_project_paths = nil if match

      if referred_project_paths != nil
        match = line.match(REGEX_PROJECT_REFERRED_PROJECT_ID)
        if match != nil && match.captures != nil && match.captures.count == 1
          (project[:referred_project_ids] ||= []) << match.captures[0]
        end
      end

      match = line.match(REGEX_PROJECT_PROJECT_REFERENCE_START)
      if match != nil && match.captures != nil && match.captures.count == 1
        referred_project_paths = match.captures[0]
      end
    end

    # Joint uitest project to projects
    if !project[:tests].nil? && project[:tests].include?(Tests::UITEST) && !project[:referred_project_ids].nil?
      project[:referred_project_ids].each do |project_id|
        referred_project = project_with_id(project_id)
        next unless referred_project

        (referred_project[:uitest_projects] ||= []) << project[:id]
      end
    end
  end

  def mdtool_configuration(project_configuration)
    config, platform = project_configuration.split('|')
    (mdtool_config ||= []) << config

    if !platform.eql?("AnyCPU") && !platform.eql?("Any CPU")
      mdtool_config << platform
    end

    mdtool_config.join('|')
  end

  def mdtool_build_command(action, project_configuration, solution, project = nil)
    raise "Undefined mdtool action found (#{action})" unless ['build', 'archive'].include? action

    command = [
      MDTOOL_PATH,
      action,
      "\"-c:#{mdtool_configuration(project_configuration)}\"",
      "\"#{solution}\""
    ]
    command << "\"-p:#{project}\"" if project
    return command
  end

  def should_generate_archives?(architectures)
    return true if architectures.nil? || architectures.empty? # default is armv7
    architectures && architectures.select { |x| x.downcase.start_with? 'arm' }.count == architectures.count
  end

  def project_with_id(id)
    return nil unless @solution

    @solution[:projects].each do |project|
      return project if project[:id].casecmp(id) == 0
    end
    return nil
  end

  def export_artifact(assembly_name, output_path, extension)
    artifact_path = Dir[File.join(output_path, "#{assembly_name}#{extension}")].first

    return nil if artifact_path == nil || !File.exists?(artifact_path)
    artifact_path
  end

  def latest_archive_path(project_name)
    default_archives_path = File.join(ENV['HOME'], 'Library/Developer/Xcode/Archives')
    raise "No default Xcode archive path found at #{default_archives_path}" unless File.exist? default_archives_path

    latest_archive = nil
    latest_archive_date = nil

    archives = Dir[File.join(default_archives_path, "**/#{project_name} *.xcarchive")]
    archives.each do |archive_path|
      match = archive_path.match(REGEX_ARCHIVE_DATE_TIME)

      if match != nil && match.captures != nil && match.captures.size == 1
        date = DateTime.strptime(match.captures[0], '%m-%d-%y %l.%M %p')

        if !latest_archive_date || latest_archive_date < date
          latest_archive_date = date
          latest_archive = archive_path
        end
      end
    end

    latest_archive
  end
end
