require 'pathname'
require 'fileutils'

require_relative './analyzer'

# -----------------------
# --- Constants
# -----------------------

MDTOOL_PATH = "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\""
XBUILD_NAME = 'xbuild'
MDTOOL_NAME = 'mdtool'

# -----------------------
# --- Builder
# -----------------------

class Builder
  def initialize(project_path, configuration, platform)
    fail 'Empty path provided' if project_path.to_s == ''
    fail "File (#{project_path}) not exist" unless File.exist? project_path

    fail 'No configuration provided' if configuration.to_s == ''
    fail 'No platform provided' if platform.to_s == ''

    @project_path = project_path
    @configuration = configuration
    @platform = platform
  end

  def clean!

    # Collect project information

    projects_to_clean = []
    if is_project_solution
      projects_to_clean = SolutionAnalyzer.new(@project_path).collect_projects(@configuration, @platform)
    else
      projects_to_clean << ProjectAnalyzer.new(@project_path).analyze(@configuration, @platform)
    end

    # Clean projects

    projects_to_clean.each do |project_to_clean|
      command = generate_clean_command(project_to_clean)

      puts
      puts "command: #{command}"
      puts

      system(command)
      fail 'Clean failed' unless $?.success?
    end
  end

  def build!

    # Collect projects to build

    projects_to_build = []
    if is_project_solution
      projects_to_build = SolutionAnalyzer.new(@project_path).collect_projects(@configuration, @platform)
    else
      projects_to_build << ProjectAnalyzer.new(@project_path).analyze(@configuration, @platform)
    end

    # Build projects

    built_projects = []

    projects_to_build.each do |project_to_build|
      command = generate_build_command(project_to_build)

      puts
      puts "command: #{command}"
      puts

      system(command)
      fail 'Build failed' unless $?.success?

      # mdtool only creates .xcarchive, we need to manully export the .ipa file
      if project_to_build[:api] == MONOTOUCH_API_NAME && project_to_build[:build_ipa]

      end

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
        "/p:Platform=\"#{project_hash[:platform]}\"",
        "/p:OutputPath=\"#{project_hash[:output_path]}/\""
    ]

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
        "/p:OutputPath=\"#{project_hash[:output_path]}/\""
    ]

    cmd << "/p:Platform=\"#{project_hash[:platform]}\"" unless project_hash[:is_test]

    cmd.join(' ')
  end

end
