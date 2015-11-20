require 'optparse'
require 'pathname'
require 'timeout'

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
    fail_with_message('failed to get xcode version') unless xcode_version
  end
  version
end

def build_project!(builder, project_path, configuration, platform)
  # Build project
  output_path = File.join('bin', platform, configuration)

  params = []
  case builder
  when 'xbuild'
    params << 'xbuild'
    params << "\"#{project_path}\""
    params << '/t:Build'
    params << "/p:Configuration=\"#{configuration}\""
    params << "/p:Platform=\"#{platform}\""
    params << "/p:OutputPath=\"#{output_path}/\""
  when 'mdtool'
    params << "#{@mdtool}"
    params << '-v build'
    params << "\"#{project_path}\""
    params << "--configuration:\"#{configuration}|#{platform}\""
    params << '--target:Build'
  else
    fail_with_message('Invalid build tool detected')
  end

  puts "#{params.join(' ')}"
  system("#{params.join(' ')}")
  fail_with_message('Build failed') unless $?.success?

  # Get the build path
  project_directory = File.dirname(project_path)
  File.join(project_directory, output_path)
end

def clean_project!(builder, project_path, configuration, platform, is_test)
  # clean project
  params = []
  case builder
  when 'xbuild'
    params << 'xbuild'
    params << "\"#{project_path}\""
    params << '/t:Clean'
    params << "/p:Configuration=\"#{configuration}\""
    params << "/p:Platform=\"#{platform}\"" unless is_test
  when 'mdtool'
    params << "#{@mdtool}"
    params << '-v build'
    params << "\"#{project_path}\""
    params << '--target:Clean'
    params << "--configuration:\"#{configuration}|#{platform}\"" unless is_test
    params << "--configuration:\"#{configuration}\"" if is_test
  else
    fail_with_message('Invalid build tool detected')
  end

  puts "#{params.join(' ')}"
  system("#{params.join(' ')}")
  fail_with_message('Clean failed') unless $?.success?
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

def export_app(build_path)
  app_path = Dir[File.join(build_path, '/**/*.app')].first
  return nil unless app_path

  full_path = Pathname.new(app_path).realpath.to_s
  return nil unless full_path
  return nil unless File.exist? full_path
  full_path
end

def export_dll(test_build_path)
  dll_path = Dir[File.join(test_build_path, '/**/*.dll')].first
  return nil unless dll_path

  full_path = Pathname.new(dll_path).realpath.to_s
  return nil unless full_path
  return nil unless File.exist? full_path
  full_path
end

def shutdown_simulator!(xcode_major_version)
  all_has_shutdown_state = simulators_has_shutdown_state?
  return if all_has_shutdown_state

  shut_down_cmd = 'killall Simulator' if xcode_major_version == 7
  shut_down_cmd = 'killall "iOS Simulator"' if xcode_major_version == 6
  fail_with_message("invalid xcode_major_version (#{xcode_major_version})") unless shut_down_cmd

  `#{shut_down_cmd}`
  fail_with_message("#{shut_down_cmd} -- failed") unless $?.success?

  begin
    Timeout.timeout(60) do
      loop do
        sleep 1 # second
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
  simulator_cmd = '/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app' if xcode_major_version == 7
  simulator_cmd = '/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Applications/iPhone Simulator.app' if xcode_major_version == 6
  fail_with_message("invalid xcode_major_version (#{xcode_major_version})") unless simulator_cmd

  `open #{simulator_cmd} --args -CurrentDeviceUDID #{simulator[:udid]}`
  fail_with_message("open \"#{simulator_cmd}\" --args -CurrentDeviceUDID #{simulator[:udid]} -- failed") unless $?.success?

  begin
    Timeout.timeout(60) do
      loop do
        sleep 1 # seconds
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
  test_project: nil,
  configuration: nil,
  platform: nil,
  builder: nil,
  clean_build: true,
  device: nil,
  os: nil
}

parser = OptionParser.new do|opts|
  opts.banner = 'Usage: step.rb [options]'
  opts.on('-s', '--project path', 'Project path') { |s| options[:project] = s unless s.to_s == '' }
  opts.on('-t', '--test project', 'Test project') { |t| options[:test_project] = t unless t.to_s == '' }
  opts.on('-c', '--configuration config', 'Configuration') { |c| options[:configuration] = c unless c.to_s == '' }
  opts.on('-p', '--platform platform', 'Platform') { |p| options[:platform] = p unless p.to_s == '' }
  opts.on('-b', '--builder builder', 'Builder') { |b| options[:builder] = b unless b.to_s == '' }
  opts.on('-i', '--clean build', 'Clean build') { |i| options[:clean_build] = false if to_bool(i) == false }
  opts.on('-d', '--device device', 'Device') { |d| options[:device] = d unless d.to_s == '' }
  opts.on('-o', '--os os', 'OS') { |o| options[:os] = o unless o.to_s == '' }
  opts.on('-h', '--help', 'Displays Help') do
    exit
  end
end
parser.parse!

fail_with_message('No project file found') unless options[:project] && File.exist?(options[:project])
fail_with_message('No test_project file found') unless options[:test_project] && File.exist?(options[:test_project])
fail_with_message('configuration not specified') unless options[:configuration]
fail_with_message('platform not specified') unless options[:platform]
fail_with_message('builder not specified') unless options[:builder]
fail_with_message('simulator_device not specified') unless options[:device]
fail_with_message('simulator_os_version not specified') unless options[:os]

udid, state = simulator_udid_and_state(options[:device], options[:os])
fail_with_message('failed to get simulator udid') unless udid || state

simulator = {
  name: options[:device],
  udid: udid,
  os: options[:os]
}

ENV['IOS_SIMULATOR_UDID'] = udid

xcode_version = xcode_major_version!

#
# Print configs
puts
puts '========== Configs =========='
puts " * project: #{options[:project]}"
puts " * test_project: #{options[:test_project]}"
puts " * configuration: #{options[:configuration]}"
puts " * platform: #{options[:platform]}"
puts " * builder: #{options[:builder]}"
puts " * clean_build: #{options[:clean_build]}"
puts " * simulator_device: #{options[:device]}"
puts " * simulator_UDID: #{udid}"
puts " * simulator_os: #{options[:os]}"

if options[:clean_build]
  #
  # Cleaning the project
  puts
  puts "==> Cleaning project: #{options[:project]}"
  clean_project!(options[:builder], options[:project], options[:configuration], options[:platform], false)

  puts
  puts "==> Cleaning test project: #{options[:test_project]}"
  clean_project!(options[:builder], options[:test_project], options[:configuration], options[:platform], true)
end

#
# Build project
puts
puts "==> Building project: #{options[:project]}"
build_path = build_project!(options[:builder], options[:project], options[:configuration], options[:platform])
fail_with_message('Failed to locate build path') unless build_path

app_path = export_app(build_path)
fail_with_message('failed to get .app path') unless app_path
puts "  (i) .app path: #{app_path}"

#
# Build UITest
puts
puts "==> Building test project: #{options[:test_project]}"
test_build_path = build_project!(options[:builder], options[:test_project], options[:configuration], options[:platform])
fail_with_message('failed to get test build path') unless test_build_path

dll_path = export_dll(test_build_path)
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
