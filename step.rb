require 'optparse'
require 'pathname'
require 'timeout'

require_relative 'xamarin-builder/builder'

@mdtool = "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\""
@mono = '/Library/Frameworks/Mono.framework/Versions/Current/bin/mono'
@nuget = '/Library/Frameworks/Mono.framework/Versions/Current/bin/nuget'

# -----------------------
# --- functions
# -----------------------

def fail_with_message(message)
  `envman add --key BITRISE_XAMARIN_TEST_RESULT --value failed`

  puts "\e[31m#{message}\e[0m"
  exit(1)
end

def error_with_message(message)
  puts "\e[31m#{message}\e[0m"
end

def to_bool(value)
  return true if value == true || value =~ (/^(true|t|yes|y|1)$/i)
  return false if value == false || value.nil? || value == '' || value =~ (/^(false|f|no|n|0)$/i)
  fail_with_message("Invalid value for Boolean: \"#{value}\"")
end

def xcode_major_version!
  out = `xcodebuild -version`
  begin
    version = out.split("\n")[0].strip.split(' ')[1].strip.split('.')[0].to_i
  rescue
    fail_with_message('failed to get xcode version') unless version
  end
  version
end

def simulator_udid_and_state(simulator_device, os_version)
  os_found = false
  os_regex = "-- #{os_version} --"
  os_separator_regex = '-- iOS \d.\d --'
  device_regex = "#{simulator_device}" + '\s*\(([\w|-]*)\)\s*\(([\w]*)\)'

  out = `xcrun simctl list | grep -i --invert-match 'unavailable'`
  out.each_line do |line|
    os_separator_match = line.match(os_separator_regex)
    os_found = false unless os_separator_match.nil?

    os_match = line.match(os_regex)
    os_found = true unless os_match.nil?

    next unless os_found

    match = line.match(device_regex)
    unless match.nil?
      udid, state = match.captures
      return udid, state
    end
  end
  nil
end

def simulators_has_shutdown_state?
  all_has_shutdown_state = true
  regex = '\s*\(([\w|-]*)\)\s*\(([\w]*)\)'
  out = `xcrun simctl list`
  out.each_line do |line|
    match = line.match(regex)
    unless match.nil?
      _udid, state = match.captures
      all_has_shutdown_state = false if state != 'Shutdown'
    end
  end
  all_has_shutdown_state
end

def shutdown_simulator!(xcode_major_version)
  all_has_shutdown_state = simulators_has_shutdown_state?
  return if all_has_shutdown_state

  shut_down_cmd = 'killall Simulator'
  shut_down_cmd = 'killall "iOS Simulator"' if xcode_major_version == 6
  fail_with_message("invalid xcode_major_version (#{xcode_major_version})") unless shut_down_cmd

  `#{shut_down_cmd}`
  fail_with_message("#{shut_down_cmd} -- failed") unless $?.success?

  begin
    Timeout.timeout(300) do
      loop do
        sleep 2 # second
        all_has_shutdown_state = simulators_has_shutdown_state?
        puts '    => waiting for shutdown ...'

        break if all_has_shutdown_state
      end
    end
  rescue Timeout::Error
    fail_with_message('simulator shutdown timed out')
  end
end

def boot_simulator!(simulator, xcode_major_version)
  simulator_cmd = '/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app'
  simulator_cmd = '/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Applications/iPhone Simulator.app' if xcode_major_version == 6
  fail_with_message("invalid xcode_major_version (#{xcode_major_version})") unless simulator_cmd

  `open #{simulator_cmd} --args -CurrentDeviceUDID #{simulator[:udid]}`
  fail_with_message("open \"#{simulator_cmd}\" --args -CurrentDeviceUDID #{simulator[:udid]} -- failed") unless $?.success?

  begin
    Timeout.timeout(300) do
      loop do
        sleep 2 # seconds
        out = `xcrun simctl openurl #{simulator[:udid]} https://www.google.com 2>&1`
        puts '    => waiting for boot ...'

        break if out == ''
      end
    end
  rescue Timeout::Error
    fail_with_message('simulator boot timed out')
  end
  sleep 2
end

def copy_app_to_simulator!(simulator, app_path, xcode_major_version)
  puts '  => shutdown simulators'
  shutdown_simulator!(xcode_major_version)

  puts "  => erase simulator #{simulator}"
  `xcrun simctl erase #{simulator[:udid]}`
  fail_with_message("xcrun simctl erase #{simulator[:udid]} -- failed") unless $?.success?

  puts "  => boot simulator #{simulator}"
  boot_simulator!(simulator, xcode_major_version)

  puts "  => install .app #{app_path} to #{simulator}"
  `xcrun simctl install #{simulator[:udid]} #{app_path}`
  fail_with_message("xcrun simctl install #{simulator[:udid]} #{app_path} -- failed") unless $?.success?
end

def run_unit_test!(dll_path)
  # nunit-console.exe Test.dll /xml=Test-results.xml /out=Test-output.txt

  nunit_path = ENV['NUNIT_PATH']
  fail_with_message('No NUNIT_PATH environment specified') unless nunit_path

  nunit_console_path = File.join(nunit_path, 'nunit3-console.exe')
  system("#{@mono} #{nunit_console_path} #{dll_path}")
  unless $?.success?
    work_dir = ENV['BITRISE_SOURCE_DIR']
    result_log = File.join(work_dir, 'TestResult.xml')
    file = File.open(result_log)
    contents = file.read
    file.close
    puts
    puts "result: #{contents}"
    puts
    fail_with_message("#{@mono} #{nunit_console_path} #{dll_path} -- failed")
  end
end

# -----------------------
# --- main
# -----------------------

#
# Input validation
options = {
    project: nil,
    configuration: nil,
    platform: nil,
    clean_build: true,
    device: nil,
    os: nil
}

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: step.rb [options]'
  opts.on('-s', '--project path', 'Project path') { |s| options[:project] = s unless s.to_s == '' }
  opts.on('-c', '--configuration config', 'Configuration') { |c| options[:configuration] = c unless c.to_s == '' }
  opts.on('-p', '--platform platform', 'Platform') { |p| options[:platform] = p unless p.to_s == '' }
  opts.on('-i', '--clean build', 'Clean build') { |i| options[:clean_build] = false unless to_bool(i) }
  opts.on('-d', '--device device', 'Device') { |d| options[:device] = d unless d.to_s == '' }
  opts.on('-o', '--os os', 'OS') { |o| options[:os] = o unless o.to_s == '' }
  opts.on('-h', '--help', 'Displays Help') do
    exit
  end
end
parser.parse!

#
# Print configs
puts
puts '========== Configs =========='
puts " * project: #{options[:project]}"
puts " * configuration: #{options[:configuration]}"
puts " * platform: #{options[:platform]}"
puts " * clean_build: #{options[:clean_build]}"
puts " * simulator_device: #{options[:device]}"
puts " * simulator_os: #{options[:os]}"

#
# Validate inputs
fail_with_message('No project file found') unless options[:project] && File.exist?(options[:project])
fail_with_message('configuration not specified') unless options[:configuration]
fail_with_message('platform not specified') unless options[:platform]
fail_with_message('simulator_device not specified') unless options[:device]
fail_with_message('simulator_os_version not specified') unless options[:os]

udid, state = simulator_udid_and_state(options[:device], options[:os])
fail_with_message('failed to get simulator udid') unless udid || state

puts " * simulator_UDID: #{udid}"

simulator = {
    name: options[:device],
    udid: udid,
    os: options[:os]
}

ENV['IOS_SIMULATOR_UDID'] = udid

xcode_version = xcode_major_version!

#
# Main
projects_to_test = []

if (File.extname(options[:project]) == '.sln')
  projects = SolutionAnalyzer.new(options[:project]).collect_projects(options[:configuration], options[:platform])
  projects.each do |project|
    if project[:api] == MONOTOUCH_API_NAME || project[:api] == XAMARIN_IOS_API_NAME && project[:related_test_project]
      test_project = ProjectAnalyzer.new(project[:related_test_project]).analyze(options[:configuration], options[:platform])

      projects_to_test << {
          project: project,
          test_project: test_project
      }
    end
  end
else
  project = ProjectAnalyzer.new(options[:project]).analyze(options[:configuration], options[:platform])
  if project[:related_test_project]
    test_project = ProjectAnalyzer.new(project[:related_test_project]).analyze(options[:configuration], options[:platform])

    projects_to_test << {
        project: project,
        test_project: test_project
    }
  end
end

fail 'No project and related test project found' if projects_to_test.count == 0

projects_to_test.each do |project_to_test|
  project = project_to_test[:project]
  test_project = project_to_test[:test_project]

  puts
  puts " ** project to test: #{project[:path]}"
  puts " ** related test project: #{test_project[:path]}"

  builder = Builder.new(project[:path], project[:configuration], project[:platform])
  test_builder = Builder.new(test_project[:path], test_project[:configuration], test_project[:platform])

  if options[:clean_build]
    builder.clean!
    test_builder.clean!
  end

#
# Build project
  puts
  puts "==> Building project: #{project[:path]}"

  built_projects = builder.build!

  app_path = nil

  built_projects.each do |project|
    if project[:api] == MONOTOUCH_API_NAME || project[:api] == XAMARIN_IOS_API_NAME && !project[:is_test]
      app_path = builder.export_app(project[:output_path])
    end
  end

  fail_with_message('failed to get .app path') unless app_path
  puts "  (i) .app path: #{app_path}"

#
# Build UITest
  puts
  puts "==> Building test project: #{test_project}"

  built_projects = test_builder.build!

  dll_path = nil

  built_projects.each do |project|
    if project[:is_test]
      dll_path = test_builder.export_dll(project[:output_path])
    end
  end


  fail_with_message('failed to get .dll path') unless dll_path
  puts "  (i) .dll path: #{dll_path}"

#
# Copy .app to simulator
  puts
  puts '=> copy .app to simulator'
  copy_app_to_simulator!(simulator, app_path, xcode_version)

#
# Run unit test
  puts
  puts '=> run unit test'
  run_unit_test!(dll_path)
end

#
# Set output envs
work_dir = ENV['BITRISE_SOURCE_DIR']
result_log = File.join(work_dir, 'TestResult.xml')

puts
puts '(i) The result is: succeeded'
system('envman add --key BITRISE_XAMARIN_TEST_RESULT --value succeeded') if work_dir

puts
puts "(i) The test log is available at: #{result_log}"
system("envman add --key BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT --value #{result_log}") if work_dir
