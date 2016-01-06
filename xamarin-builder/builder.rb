require 'pathname'
require 'fileutils'

require_relative './analyzer'

MDTOOL_PATH = "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\""

XBUILD_NAME = 'xbuild'
MDTOOL_NAME = 'mdtool'

MONO_ANDROID_API_NAME = 'Mono.Android'
MONOTOUCH_API_NAME = 'monotouch'
XAMARIN_IOS_API_NAME = 'Xamarin.iOS'


# define class Builder
class Builder
  def initialize(project_path, configuration, platform)
    @project_path = project_path
    @configuration = configuration
    @platform = platform
  end

  def clean!

    # Collect projects to clean

    projects = []

    if is_project_solution
      solution = Analyzer.new(@project_path).analyze_solution
      solution.projects.each do |project|
        mapping = project.mapping
        config = mapping["#{@configuration}|#{@platform}"]
        fail "No mapping found for config: #{@configuration}|#{@platform}" unless config

        configuration, platform = config.split('|')
        fail "No configuration, platform found for config: #{config}" unless configuration || platform

        projects << {
            path: project.path,
            configuration: configuration,
            platform: platform
        }
      end
    else
      projects << {
          path: @project_path,
          configuration: @configuration,
          platform: @platform
      }
    end

    # Collect project information

    projects_to_clean= []

    projects.each do |project_to_clean|
      analyzer = Analyzer.new(project_to_clean[:path])

      is_test = analyzer.test_project?
      api = analyzer.xamarin_api

      project_to_clean[:api] = api
      project_to_clean[:is_test] = is_test

      projects_to_clean << project_to_clean
    end

    # Clean projects

    projects_to_clean.each do |project_to_clean|
      command = generate_clean_command(project_to_clean)
      system(command)
      fail 'Clean failed' unless $?.success?
    end
  end

  def build!

    # Collect projects to build

    projects = []

    if is_project_solution
      solution = Analyzer.new(@project_path).analyze_solution
      solution.projects.each do |project|
        mapping = project.mapping
        config = mapping["#{@configuration}|#{@platform}"]
        fail "No mapping found for config: #{@configuration}|#{@platform}" unless config

        configuration, platform = config.split('|')
        fail "No configuration, platform found for config: #{config}" unless configuration || platform

        projects << {
            path: project.path,
            configuration: configuration,
            platform: platform
        }
      end
    else
      projects << {
          path: @project_path,
          configuration: @configuration,
          platform: @platform
      }
    end

    # Collect project information

    projects_to_build = []

    projects.each do |project_to_build|
      analyzer = Analyzer.new(project_to_build[:path])

      output_path = analyzer.output_path(project_to_build[:configuration], project_to_build[:platform])
      is_test = analyzer.test_project?
      api = analyzer.xamarin_api
      build_ipa = false
      if api == MONOTOUCH_API_NAME || api == XAMARIN_IOS_API_NAME
        build_ipa = analyzer.allowed_to_build_ipa(project_to_build[:configuration], project_to_build[:platform])
      end
      sign_apk = false
      if api == MONO_ANDROID_API_NAME
        sign_apk = analyzer.allowed_to_sign_android(project_to_build[:configuration], project_to_build[:platform])
      end

      project_to_build[:api] = api
      project_to_build[:output_path] = output_path
      project_to_build[:is_test] = is_test
      project_to_build[:build_ipa] = build_ipa
      project_to_build[:sign_apk] = sign_apk

      puts "project_to_build: #{project_to_build}"

      projects_to_build << project_to_build
    end

    # Build projects

    built_projects = []

    projects_to_build.each do |project_to_build|
      command = generate_build_command(project_to_build)
      puts "command: #{command}"
      system(command)
      fail 'Build failed' unless $?.success?

      project_directory = File.dirname(project_to_build[:path])
      absolute_output_path = File.join(project_directory, '**', project_to_build[:output_path], '**')

      project_to_build[:output_path] = absolute_output_path

      built_projects << project_to_build
    end

    built_projects
  end

  def export_app(output_path)
    export_artifact(output_path, '.app')
  end

  def export_dll(output_path)
    export_artifact(output_path, '.dll')
  end

  def export_apk(output_path)
    export_artifact(output_path, '.apk')
  end

  def export_ipa(output_path)
    export_artifact(output_path, '.ipa')
  end

  def export_dsym(output_path)
    export_artifact(output_path, '.app.dSYM')
  end

  def zip_dsym(dsym_path)
    name = File.basename(File.basename(dsym_path, '.*'), '.*')
    dir = File.dirname(dsym_path)
    zip = File.join(dir, "#{name}.dSYM.zip")

    system("/usr/bin/zip -rTy #{zip} #{dsym_path}")
    fail 'Failed to zip dSYM' unless $?.success?

    full_path = Pathname.new(zip).realpath.to_s
    return nil unless full_path
    return nil unless File.exist? full_path
    full_path
  end

  private

  def export_artifact(output_path, extension)
    artifact = Dir[File.join(output_path, "/*#{extension}")].first
    return nil unless artifact

    full_path = Pathname.new(artifact).realpath.to_s
    return nil unless full_path
    return nil unless File.exist? full_path
    full_path
  end

  def is_project_solution
    File.extname(@project_path) == '.sln'
  end

  def generate_build_command(project_hash)
    if project_hash[:api] == MONOTOUCH_API_NAME
      return [
          MDTOOL_NAME,
          project_hash[:path],
          '--target:Build',
          '-v build',
          "\"#{project_hash[:path]}\"",
          "--configuration:\"#{configuration}|#{platform}\""
      ].join(' ')
    end

    cmd = [
        XBUILD_NAME,
        project_hash[:path],
        "/p:Configuration=\"#{project_hash[:configuration]}\"",
        "/p:OutputPath=\"#{project_hash[:output_path]}/\""
    ]

    cmd << "/p:Platform=\"#{project_hash[:platform]}\"" unless project_hash[:is_test]
    cmd << '/t:Build' if project_hash[:api] == XAMARIN_IOS_API_NAME
    cmd << '/p:BuildIpa=true' if project_hash[:api] == XAMARIN_IOS_API_NAME && project_hash[:build_ipa]

    cmd << '/t:SignAndroidPackage' if project_hash[:api] == MONO_ANDROID_API_NAME && project_hash[:sign_apk]
    cmd << '/t:PackageForAndroid' if project_hash[:api] == MONO_ANDROID_API_NAME && !project_hash[:sign_apk]

    cmd.join(' ')
  end

  def generate_clean_command(project_hash)
    if project_hash[:api] == MONOTOUCH_API_NAME
      return [
          MDTOOL_NAME,
          project_hash[:path],
          '--target:Clean',
          '-v build',
          "\"#{project_hash[:path]}\"",
          "--configuration:\"#{project_hash[:configuration]}|#{project_hash[:platform]}\""
      ].join(' ')
    end

    cmd = [
        XBUILD_NAME,
        project_hash[:path],
        '/t:Clean',
        "/p:Configuration=\"#{project_hash[:configuration]}\"",
    ]

    cmd << "/p:Platform=\"#{project_hash[:platform]}\"" unless project_hash[:is_test]

    cmd.join(' ')
  end

end
