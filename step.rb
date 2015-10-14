require 'pathname'

# -----------------------
# --- functions
# -----------------------

def fail_with_message(message)
  ENV['BITRISE_XAMARIN_TEST_RESULT'] = 'failed'

  puts "\e[31m#{message}\e[0m"
  exit(1)
end

def error_with_message(message)
  puts "\e[31m#{message}\e[0m"
end

def xcode_major_version
  out = `xcodebuild -version`
  begin
    version = out.split("\n")[0].strip.split(' ')[1].strip.split('.')[0].to_i
  rescue
    nil
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

def all_simulator_shutteddown
  all_shotdown = true
  regex = '\s*\(([\w|-]*)\)\s*\(([\w]*)\)'
  out = `xcrun simctl list`
  out.each_line do |line|
    match = line.match(regex)
    unless match.nil?
      _udid, state = match.captures
      all_shotdown = false if state != 'Shutdown'
    end
  end
  all_shotdown
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

def shutdown_simulators(xcode_major_version)
  all_shotdown = all_simulator_shutteddown
  return 0 if all_shotdown

  `killall Simulator` if xcode_major_version == 7
  `killall "iOS Simulator"` if xcode_major_version == 6
  return 1 unless $?.success?

  loop do
    sleep 1 # second
    all_shotdown = all_simulator_shutteddown
    puts '    => waiting for shutdown ...'
    break if all_shotdown
  end
  0
end

def boot_simulator(simulator, xcode_major_version)
  simulator_cmd = ''
  simulator_cmd = '/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app' if xcode_major_version == 7
  simulator_cmd = '/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Applications/iPhone\ Simulator.app' if xcode_major_version == 6

  `open #{simulator_cmd} --args -CurrentDeviceUDID #{simulator[:udid]}`
  return 1 unless $?.success?

  loop do
    sleep 1 # seconds
    out = `xcrun simctl openurl #{simulator[:udid]} https://www.google.com 2>&1`
    puts '    => waiting for boot ...'
    break if out == ''
  end
  sleep 2
  0
end

def copy_app_to_simulator(simulator, app_path, xcode_major_version)
  puts '  => shutdown simulators'
  exit_code = shutdown_simulators(xcode_major_version)
  return 1 if exit_code != 0

  puts "  => erase simulator #{simulator}"
  `xcrun simctl erase #{simulator[:udid]}`
  return 1 unless $?.success?

  puts "  => boot simulator #{simulator}"
  exit_code = boot_simulator(simulator, xcode_major_version)
  return 1 if exit_code != 0

  puts "  => install .app #{app_path} to #{simulator}"
  `xcrun simctl install #{simulator[:udid]} #{app_path}`
  return 1 unless $?.success?
  0
end

def run_unit_test(nunit_console_path, dll_path)
  mono = '/Library/Frameworks/Mono.framework/Versions/Current/bin/mono'
  out = `#{mono} #{nunit_console_path} #{dll_path}`
  return [out, 1] unless $?.success?

  regex = 'Tests run: (?<total>\d*), Errors: (?<errors>\d*), Failures: (?<failures>\d*), Inconclusive: (?<inconclusives>\d*), Time: (?<time>\S*) seconds\n  Not run: (?<not_run>\d*), Invalid: (?<invalid>\d*), Ignored: (?<ignored>\d*), Skipped: (?<skipped>\d*)'
  match = out.match(regex)
  unless match.nil?
    _total, errors, failures, _inconclusives, _time, _not_run, _invalid, _ignored, _skipped = match.captures
    return [out, 1] unless errors.to_i == 0 && failures.to_i == 0
    return [match, 0]
  end
  [out, 1]
end

# -----------------------
# --- main
# -----------------------

# Input validation
xamarin_solution = ARGV[0]
fail_with_message('xamarin_solution not specified') unless xamarin_solution
puts "(i) xamarin_solution: #{xamarin_solution}"

xamarin_configuration = ARGV[1]
fail_with_message('xamarin_configuration not specified') unless xamarin_configuration
puts "(i) xamarin_configuration: #{xamarin_configuration}"

xamarin_platform = ARGV[2]
fail_with_message('xamarin_platform not specified') unless xamarin_platform
puts "(i) xamarin_platform: #{xamarin_platform}"

xamarin_builder = ARGV[3]
fail_with_message('xamarin_builder not specified') unless xamarin_builder
puts "(i) xamarin_builder: #{xamarin_builder}"

simulator_device = ARGV[4]
fail_with_message('simulator_device not specified') unless simulator_device
puts "(i) simulator_device: #{simulator_device}"

simulator_os_version = ARGV[5]
fail_with_message('simulator_os_version not specified') unless simulator_os_version
puts "(i) simulator_os_version: #{simulator_os_version}"

nunit_console_path = ARGV[6]
fail_with_message('nunit_console_path not specified') unless nunit_console_path
puts "(i) nunit_console_path: #{nunit_console_path}"

udid, state = simulator_udid_and_state(simulator_device, simulator_os_version)
fail_with_message('failed to get simulator udid') unless udid || state
puts "(i) simulator udid: #{udid} - state: #{state}"

simulator = {
  name: simulator_device,
  udid: udid,
  os: simulator_os_version
}

ENV['DEVICE_UDID'] = udid

if xamarin_platform != 'iPhoneSimulator'
  puts ''
  puts "(!) Given platform: \'#{xamarin_platform}\', but unit test requires platform \'iPhoneSimulator\'"
  puts '(!) Change platform to \'iPhoneSimulator\'...'
  xamarin_platform = 'iPhoneSimulator'
end

# Environments
solution_file = Pathname.new(xamarin_solution).realpath.to_s
project_root_directory = File.dirname(solution_file)
puts "(i) project_root_directory: #{project_root_directory}"

xcode_version = xcode_major_version
fail_with_message('failed to get xcode version') unless xcode_version

# Preparing build params
builders = {
  'mdtool' => '/Applications/Xamarin Studio.app/Contents/MacOS/mdtool',
  'xbuild' => '/Library/Frameworks/Mono.framework/Versions/Current/bin/xbuild'
}

puts "\n=> generating .app"
params = ["\"#{builders[xamarin_builder]}\""]
case xamarin_builder
when 'xbuild'
  params << "/p:Configuration=\"#{xamarin_configuration}\"" if xamarin_configuration
  params << "/p:Platform=\"#{xamarin_platform}\"" if xamarin_platform
  params << "/p:Target=\"#{xamarin_configuration}\"" if xamarin_configuration
  params << '/p:BuildIpa=true'
  params << '/p:ArchiveOnBuild=true'
  params << "\"#{xamarin_solution}\""
when 'mdtool'
  params << '-v build'
  params << "--configuration:\"#{xamarin_configuration}|#{xamarin_platform}\""
  params << "\"#{xamarin_solution}\""
else
  fail_with_message('Invalid build tool detected')
end

# Building
puts "\n#{params.join(' ')}"
system("#{params.join(' ')}")
fail_with_message('Build failed') unless $?.success?
puts

build_path = Dir[File.join(project_root_directory, "/**/bin/#{xamarin_platform}/#{xamarin_configuration}")].first
fail_with_message('failed to get build path') unless build_path

app_path = export_app(build_path)
fail_with_message('failed to get .app path') unless app_path
puts "  (i) .app path: #{app_path}"

test_build_path = Dir[File.join(project_root_directory, "/**/*.UITests/bin/#{xamarin_configuration}")].first
fail_with_message('failed to get test build path') unless test_build_path

dll_path = export_dll(test_build_path)
fail_with_message('failed to get .dll path') unless dll_path
puts "  (i) .dll path: #{dll_path}"

# Copy .app to simulator
puts "\n=> copy .app to simulator"
exit_code = copy_app_to_simulator(simulator, app_path, xcode_version)
fail_with_message('failed to copy .app to simulator') if exit_code != 0
puts '(i) .app successfully copied to simulator'

# Run unit test
puts "\n=> run unit test"
out, exit_code = run_unit_test(nunit_console_path, dll_path)
fail_with_message("failed to run unit test, out:\n#{out}") if exit_code != 0
puts "(i) unit test successfully runned, output:\n"
puts "\n#{out}"

# Set output envs
work_dir = ENV['BITRISE_SOURCE_DIR']
result_log = File.join(work_dir, 'TestResult.xml')
`envman add --key BITRISE_XAMARIN_TEST_RESULT --value succeeded` if work_dir
`envman add --key BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT --value #{result_log}` if work_dir
