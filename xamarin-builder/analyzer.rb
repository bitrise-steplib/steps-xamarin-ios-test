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
REGEX_PROJECT_GUID = /<ProjectGuid>(?<project_id>.*)<\/ProjectGuid>/i
REGEX_PROJECT_TYPE_GUIDS = /<ProjectTypeGuids>(?<project_type_guids>.*)<\/ProjectTypeGuids>/i
REGEX_PROJECT_OUTPUT_TYPE = /<OutputType>(?<output_type>.*)<\/OutputType>/i
REGEX_PROJECT_ASSEMBLY_NAME = /<AssemblyName>(?<assembly_name>.*)<\/AssemblyName>/i
REGEX_PROJECT_PROPERTY_GROUP_WITH_CONDITION = /<PropertyGroup Condition=\"\s*'\$\(Configuration\)\|\$\(Platform\)'\s*==\s*'(?<config>.*)\|(?<platform>.*)'\s*\">/i
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
REGEX_PROJECT_REFERENCE_XAMARIN_UITEST = /Include="Xamarin.UITest"/i
REGEX_PROJECT_REFERENCE_NUNIT_FRAMEWORK = /Include="nunit.framework"/i
REGEX_PROJECT_REFERENCE_NUNIT_LITE_FRAMEWORK = /Include="MonoTouch.NUnitLite"/i

REGEX_ARCHIVE_DATE_TIME = /\s(.*[AM]|[PM]).*\./i

class Analyzer
  @project_type_guids = {
    ios: "FEACFBD2-3405-455C-9665-78FE426C6842",
    mac: "A3F8F2AB-B479-4A4A-A458-A89E7DC349F1",
    tvos: "06FA79CB-D6CD-4721-BB4B-1BD202089C55",
    android: "EFBA0AD7-5A72-4C68-AF49-83D382785DCF"
  }

  class << self
    attr_accessor :project_type_guids
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
        when Api::IOS
          next unless project_type_filter.include? Api::IOS
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
      project[:referred_project_ids].each do |id|
        referred_project = project_with_id(id)
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
      when Api::IOS
        next unless project_type_filter.include? Api::IOS
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
      when Api::MAC
        next unless project_type_filter.include? Api::MAC
        next unless project[:output_type].eql?('exe')
        next unless project_configuration

        outputs_hash[project[:id]] = {}
        full_output_path = latest_archive_path(project[:name])

        outputs_hash[project[:id]][:xcarchive] = full_output_path if full_output_path
      when Api::ANDROID
        next unless project_type_filter.include? Api::ANDROID
        next unless project[:android_application]
        next unless project_configuration

        project_path = project[:path]
        project_dir = File.dirname(project_path)
        rel_output_dir = project[:configs][project_configuration][:output_path]
        full_output_dir = File.join(project_dir, rel_output_dir)

        package_name = project[:android_manifest_path].nil? ? '*' : android_package_name(project[:android_manifest_path])

        full_output_path = nil
        full_output_path = export_artifact(package_name, full_output_dir, '.apk') if package_name
        full_output_path = export_artifact('*', full_output_dir, '.apk') unless full_output_path

        outputs_hash[project[:id]] = {}
        outputs_hash[project[:id]][:apk] = full_output_path if full_output_path
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
          project_platform = "AnyCPU" if project_platform.eql? 'Any CPU' # Fix MS bug

          project = project_with_id(project_id)
          next unless project

          (project[:mappings] ||= {})["#{solution_configuration}|#{solution_platform}"] = "#{project_configuration}|#{project_platform}"
        end
      end

      match = line.match(REGEX_SOLUTION_GLOBAL_PROJECT_CONFIG_START)
      parse_project_configs = true if match != nil
    end
  end

  def analyze_project(project)
    project_config = nil
    referred_project_paths = nil

    File.open(project[:path]).each do |line|
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
      project_config = nil if match

      if project_config != nil
        match = line.match(REGEX_PROJECT_OUTPUT_PATH)
        if match != nil && match.captures != nil && match.captures.count == 1
          project[:configs][project_config][:output_path] = File.join(match.captures[0].split('\\'))
        end

        match = line.match(REGEX_PROJECT_MTOUCH_ARCH)
        if match != nil && match.captures != nil && match.captures.count == 1
          project[:configs][project_config][:mtouch_arch] = match.captures[0].split(',').collect { |x| x.strip || x }
        end

        match = line.match(REGEX_PROJECT_SIGN_ANDROID)
        project[:configs][project_config][:sign_android] = true if match != nil

        match = line.match(REGEX_PROJECT_IPA_PACKAGE)
        project[:configs][project_config][:ipa_package] = true if match != nil

        match = line.match(REGEX_PROJECT_BUILD_IPA)
        project[:configs][project_config][:build_ipa] = true if match != nil
      end

      match = line.match(REGEX_PROJECT_PROPERTY_GROUP_WITH_CONDITION)
      if match != nil && match.captures != nil && match.captures.count == 2
        configuration = match.captures[0].strip
        platform = match.captures[1].strip
        project_config = "#{configuration}|#{platform}"

        (project[:configs] ||= {})[project_config] = {}
      end

      # API
      match = line.match(REGEX_PROJECT_TYPE_GUIDS)
      project[:api] = identify_project_api(match.captures.first) if match != nil && match.captures != nil && match.captures.count == 1

      match = line.match(REGEX_PROJECT_REFERENCE_XAMARIN_UITEST)
      (project[:tests] ||= []) << Tests::UITEST if match != nil

      match = line.match(REGEX_PROJECT_REFERENCE_NUNIT_FRAMEWORK)
      (project[:tests] ||= []) << Tests::NUNIT if match != nil

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
    (mdtool_config ||= [] ) << config

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

    archives = Dir[File.join(default_archives_path, "**/#{project_name}*.xcarchive")]
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

  def identify_project_api(project_type_guids)
    if project_type_guids.include? Analyzer.project_type_guids[:ios]
      Api::IOS
    elsif project_type_guids.include? Analyzer.project_type_guids[:android]
      Api::ANDROID
    elsif project_type_guids.include? Analyzer.project_type_guids[:mac]
      Api::MAC
    elsif project_type_guids.include? Analyzer.project_type_guids[:tvos]
      Api::TVOS
    end
  end
end
