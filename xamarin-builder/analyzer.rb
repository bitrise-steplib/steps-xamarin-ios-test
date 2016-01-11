require 'time'
require 'pathname'

# -----------------------
# --- Constants
# -----------------------

MDTOOL_PATH = "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\""

CSPROJ_EXT = '.csproj'
SHPROJ_EXT = '.shproj'
SLN_EXT = '.sln'

SOLUTION = 'solution'
PROJECT = 'project'

REGEX_SOLUTION_PROJECTS = /Project\(\"(?<solution_id>[^\"]*)\"\) = \"(?<project_name>[^\"]*)\", \"(?<project_path>[^\"]*)\", \"(?<project_id>[^\"]*)\"/i
REGEX_SOLUTION_GLOBAL_SOLUTION_CONFIG_START = /GlobalSection\(SolutionConfigurationPlatforms\) = preSolution/i
REGEX_SOLUTION_GLOBAL_SOLUTION_CONFIG = /^\s*(?<config>[^|]*)\|(?<platform>[^|]*) =/i
REGEX_SOLUTION_GLOBAL_PROJECT_CONFIG_START = /GlobalSection\(ProjectConfigurationPlatforms\) = postSolution/i
REGEX_SOLUTION_GLOBAL_PROJECT_CONFIG = /(?<project_id>{[^}]*}).(?<config>(\w|\s)*)\|(?<platform>(\w|\s)*)\.Build.* = (?<mapped_config>(\w|\s)*)\|(?<mapped_platform>(\w|\s)*)/i
REGEX_SOLUTION_GLOBAL_CONFIG_END = /EndGlobalSection/i

REGEX_PROJECT_GUID = /<ProjectGuid>(?<project_id>.*)<\/ProjectGuid>/i
REGEX_PROJECT_OUTPUT_TYPE = /<OutputType>(?<output_type>.*)<\/OutputType>/i
REGEX_PROJECT_ASSEMBLY_NAME = /<AssemblyName>(?<assembly_name>.*)<\/AssemblyName>/i
REGEX_PROJECT_MTOUCH_ARCH = /<MtouchArch>(?<arch>.*)<\/MtouchArch>/
REGEX_PROJECT_PROPERTY_GROUP_WITH_CONDITION = /<PropertyGroup Condition=\" '\$\(Configuration\)\|\$\(Platform\)' == '(?<config>(\w|\s)*)\|(?<platform>(\w|\s)*)' \">/i
REGEX_PROJECT_PROPERTY_GROUP_END = /<\/PropertyGroup>/i
REGEX_PROJECT_OUTPUT_PATH = /<OutputPath>(?<output_path>.*)<\/OutputPath>/i
REGEX_PROJECT_IPA_PACKAGE = /<IpaPackageName>/i
REGEX_PROJECT_BUILD_IPA = /<BuildIpa>True<\/BuildIpa>/i
REGEX_PROJECT_ANDROID_APPLICATION= /<AndroidApplication>True<\/AndroidApplication>/i
REGEX_PROJECT_SIGN_ANDROID = /<AndroidKeyStore>True<\/AndroidKeyStore>/i
REGEX_PROJECT_REFERENCE_XAMARIN_IOS = /Include="Xamarin.iOS"/i
REGEX_PROJECT_REFERENCE_XAMARIN_ANDROID = /Include="Mono.Android"/i
REGEX_PROJECT_REFERENCE_XAMARIN_UITEST = /Include="Xamarin.UITest"/i

REGEX_PROJECT_PROJECT_REFERENCE_START = /<ProjectReference Include="(?<project_path>.*)">/i
REGEX_PROJECT_PROJECT_REFERENCE_END = /<\/ProjectReference>/i
REGEX_PROJECT_REFERRED_PROJECT_ID = /<Project>(?<id>.*)<\/Project>/i

REGEX_ARCHIVE_DATE_TIME = /\s(.*[AM]|[PM]).*\./i

class Analyzer
  def analyze(path)
    @path = path

    case type
      when SOLUTION
        analyze_solution(@path)
      when PROJECT
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

  def build_commands(config, platform, project_type_filter)
    configuration = "#{config}|#{platform}"
    build_commands = []

    @solution[:projects].each do |project|
      next unless project[:mappings]
      project_configuration = project[:mappings][configuration]

      case project[:api]
        when 'ios'
          next unless project_type_filter.include? 'ios'
          next unless project[:output_type].eql?('exe')
          unless project_configuration
            puts "Skipping: No configuration mapping found for (#{configuration}) in project #{project[:name]}" 
            next
          end

          archs = project[:configs][project_configuration][:mtouch_arch]
          generate_archive = archs && archs.select { |x| x.downcase.start_with? 'arm' }.count == archs.count

          build_commands << [
              MDTOOL_PATH,
              generate_archive ? 'archive' : 'build',
              "\"-c:#{configuration}\"",
              @solution[:path],
              "-p:#{project[:name]}"
          ].join(' ')
        when 'android'
          next unless project_type_filter.include? 'android'
          next unless project[:android_application]
          unless project_configuration
            puts "Skipping: No configuration mapping found for (#{configuration}) in project #{project[:name]}"
            next
          end
          sign_android = project[:configs][project_configuration][:sign_android]

          build_commands << [
              MDTOOL_PATH,
              'build',
              "\"-c:#{configuration}\"",
              @solution[:path],
              "-p:#{project[:name]}"
          ].join(' ')

          build_commands << [
            'xbuild',
            sign_android ? '/t:SignAndroidPackage' : '/t:PackageForAndroid',
            "/p:Configuration=#{project_configuration.split('|').first}",
            "/p:Platform=#{project_configuration.split('|').last}",
            project[:path]
          ].join(' ')
        else
          next
      end
    end

    build_commands
  end

  def test_commands(config, platform)
    configuration = "#{config}|#{platform}"
    build_command = nil

    @solution[:projects].each do |project|
      next unless project[:mappings]
      project_configuration = project[:mappings][configuration]

      next unless project[:api] == 'uitest'
      unless project_configuration
        puts "Skipping: No configuration mapping found for (#{configuration}) in project #{project[:name]}"
        next
      end

      build_command = [
          MDTOOL_PATH,
          'build',
          "\"-c:#{configuration}\"",
          @solution[:path],
      ].join(' ')
    end

    build_command
  end

  def collect_generated_files(config, platform, project_type_filter)
    outputs_hash = {}

    configuration = "#{config}|#{platform}"

    @solution[:projects].each do |project|
      next unless project[:mappings]
      project_configuration = project[:mappings][configuration]

      case project[:api]
        when 'ios'
          next unless project_type_filter.include? 'ios'
          next unless project[:output_type].eql?('exe')
          next unless project_configuration

          archs = project[:configs][project_configuration][:mtouch_arch]
          generate_archive = archs && archs.select { |x| x.downcase.start_with? 'arm' }.count == archs.count

          project_path = project[:path]
          project_dir = File.dirname(project_path)
          rel_output_dir = project[:configs][project_configuration][:output_path]
          full_output_dir = File.join(project_dir, rel_output_dir)

          outputs_hash[project[:id]] = {}
          if generate_archive
            full_output_path = latest_archive_path(project[:name])

            next unless full_output_path

            outputs_hash[project[:id]][:xcarchive] = full_output_path
          else
            full_output_path = export_artifact(project[:assembly_name], full_output_dir, '.app')

            next unless full_output_path

            outputs_hash[project[:id]][:app] = full_output_path

            # Search for test dll
            next unless project[:uitest_projects]

            project[:uitest_projects].each do |test_project_id|
              test_project = project_with_id(test_project_id)
              test_project_configuration = test_project[:mappings][configuration]

              next unless test_project_configuration

              test_project_path = test_project[:path]
              test_project_dir = File.dirname(test_project_path)
              test_rel_output_dir = test_project[:configs][test_project_configuration][:output_path]
              test_full_output_dir = File.join(test_project_dir, test_rel_output_dir)

              test_full_output_path = export_artifact(test_project[:assembly_name], test_full_output_dir, '.dll')

              (outputs_hash[project[:id]][:uitests] ||= []) << test_full_output_path
            end
          end
        when 'android'
          next unless project_type_filter.include? 'android'
          next unless project[:android_application]
          next unless project_configuration

          project_path = project[:path]
          project_dir = File.dirname(project_path)
          rel_output_dir = project[:configs][project_configuration][:output_path]
          full_output_dir = File.join(project_dir, rel_output_dir)

          full_output_path = export_artifact('*', full_output_dir, '.apk')

          next unless full_output_path

          outputs_hash[project[:id]] = {}
          outputs_hash[project[:id]][:apk] = full_output_path

          # Search for test dll
          next unless project[:uitest_projects]

          project[:uitest_projects].each do |test_project_id|
            test_project = project_with_id(test_project_id)
            test_project_configuration = test_project[:mappings][configuration]

            next unless test_project_configuration

            test_project_path = test_project[:path]
            test_project_dir = File.dirname(test_project_path)
            test_rel_output_dir = test_project[:configs][test_project_configuration][:output_path]
            test_full_output_dir = File.join(test_project_dir, test_rel_output_dir)

            test_full_output_path = export_artifact(test_project[:assembly_name], test_full_output_dir, '.dll')

            (outputs_hash[project[:id]][:uitests] ||= []) << test_full_output_path
          end
        else
          next
      end
    end

    outputs_hash
  end

  private

  def type
    return SOLUTION if @path.downcase.end_with? SLN_EXT
    return PROJECT if @path.downcase.end_with? CSPROJ_EXT
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
        else
          puts "Warning: Skipping #{project_path}: directory or not found on file system"
        end
      end

      # Solution configs
      match = line.match(REGEX_SOLUTION_GLOBAL_CONFIG_END)
      parse_solution_configs = false if match != nil

      if parse_solution_configs
        match = line.match(REGEX_SOLUTION_GLOBAL_SOLUTION_CONFIG)
        if match != nil && match.captures != nil && match.captures.count == 2
          (@solution[:configs] ||= []) << "#{match.captures[0]}|#{match.captures[1].delete(' ')}"
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

          project = project_with_id(project_id)
          (project[:mappings] ||= {})["#{match.captures[1]}|#{match.captures[2].delete(' ')}"] = "#{match.captures[3]}|#{match.captures[4].strip.delete(' ')}"
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
        project_config = "#{match.captures[0]}|#{match.captures[1].delete(' ')}"

        (project[:configs] ||= {})[project_config] = {}
      end

      # API
      match = line.match(REGEX_PROJECT_REFERENCE_XAMARIN_IOS)
      project[:api] = 'ios' if match != nil

      match = line.match(REGEX_PROJECT_REFERENCE_XAMARIN_ANDROID)
      project[:api] = 'android' if match != nil

      match = line.match(REGEX_PROJECT_REFERENCE_XAMARIN_UITEST)
      project[:api] = 'uitest' if match != nil

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
    if project[:api].eql? 'uitest'
      project[:referred_project_ids].each do |project_id|
        referred_project = project_with_id(project_id)
        next unless referred_project

        (referred_project[:uitest_projects] ||= []) << project[:id]
      end
    end
  end

  def project_with_id(id)
    return nil unless @solution

    @solution[:projects].each do |project|
      return project if project[:id].casecmp(id) == 0
    end
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
end
