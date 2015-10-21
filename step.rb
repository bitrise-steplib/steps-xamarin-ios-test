require 'optparse'
require 'pathname'

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

def xcode_major_version!
  out = `xcodebuild -version`
  begin
    version = out.split("\n")[0].strip.split(' ')[1].strip.split('.')[0].to_i
  rescue
    fail_with_message('failed to get xcode version') unless xcode_version
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

def shutdown_simulator(xcode_major_version)
  all_has_shutdown_state = simulators_has_shutdown_state?
  return 0 if all_has_shutdown_state

  `killall Simulator` if xcode_major_version == 7
  `killall "iOS Simulator"` if xcode_major_version == 6
  return 1 unless $?.success?

  boot_start = Time.now
  loop do
    sleep 1 # second
    all_has_shutdown_state = simulators_has_shutdown_state?
    puts '    => waiting for shutdown ...'

    return 1 if Time.now - boot_start > 60

    break if all_has_shutdown_state
  end
  0
end

def boot_simulator(simulator, xcode_major_version)
  simulator_cmd = '/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app' if xcode_major_version == 7
  simulator_cmd = '/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Applications/iPhone\ Simulator.app' if xcode_major_version == 6
  return 1 unless simulator_cmd

  `open #{simulator_cmd} --args -CurrentDeviceUDID #{simulator[:udid]}`
  return 1 unless $?.success?

  boot_start = Time.now
  loop do
    sleep 1 # seconds
    out = `xcrun simctl openurl #{simulator[:udid]} https://www.google.com 2>&1`
    puts '    => waiting for boot ...'

    return 1 if Time.now - boot_start > 60

    break if out == ''
  end
  sleep 2
  0
end

def copy_app_to_simulator(simulator, app_path, xcode_major_version)
  puts '  => shutdown simulators'
  exit_code = shutdown_simulator(xcode_major_version)
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
options = {
  solution: nil,
  configuration: nil,
  platform: nil,
  builder: nil,
  device: nil,
  os: nil,
  nunit_path: nil
}

parser = OptionParser.new do|opts|
  opts.banner = 'Usage: step.rb [options]'
  opts.on('-s', '--solution path', 'Solution path') { |s| options[:solution] = s unless s.to_s == '' }
  opts.on('-c', '--configuration config', 'Configuration') { |c| options[:configuration] = c unless c.to_s == '' }
  opts.on('-p', '--platform platform', 'Platform') { |p| options[:platform] = p unless p.to_s == '' }
  opts.on('-b', '--builder builder', 'Builder') { |b| options[:builder] = b unless b.to_s == '' }
  opts.on('-d', '--device device', 'Device') { |d| options[:device] = d unless d.to_s == '' }
  opts.on('-o', '--os os', 'OS') { |o| options[:os] = o unless o.to_s == '' }
  opts.on('-n', '--nunit path', 'NUnit path') { |n| options[:nunit_path] = n unless n.to_s == '' }
  opts.on('-h', '--help', 'Displays Help') do
    puts opts
    exit
  end
end
parser.parse!

fail_with_message('xamarin_solution not specified') unless options[:solution]
puts "(i) xamarin_solution: #{options[:solution]}"

fail_with_message('xamarin_configuration not specified') unless options[:configuration]
puts "(i) xamarin_configuration: #{options[:configuration]}"

fail_with_message('xamarin_platform not specified') unless options[:platform]
puts "(i) xamarin_platform: #{options[:platform]}"

fail_with_message('xamarin_builder not specified') unless options[:builder]
puts "(i) xamarin_builder: #{options[:builder]}"

fail_with_message('simulator_device not specified') unless options[:device]
puts "(i) simulator_device: #{options[:device]}"

fail_with_message('simulator_os_version not specified') unless options[:os]
puts "(i) simulator_os_version: #{options[:os]}"

fail_with_message('nunit_console_path not specified') unless options[:nunit_path]
puts "(i) nunit_console_path: #{options[:nunit_path]}"

udid, state = simulator_udid_and_state(options[:device], options[:os])
fail_with_message('failed to get simulator udid') unless udid || state
puts "(i) simulator udid: #{udid} - state: #{state}"

simulator = {
  name: options[:device],
  udid: udid,
  os: options[:os]
}

ENV['IOS_SIMULATOR_UDID'] = udid

if options[:platform] != 'iPhoneSimulator'
  puts ''
  puts "(!) Given platform: \'#{options[:platform]}\', but unit test requires platform \'iPhoneSimulator\'"
  puts '(!) Change platform to \'iPhoneSimulator\'...'
  options[:platform] = 'iPhoneSimulator'
end

# Environments
solution_file = Pathname.new(options[:solution]).realpath.to_s
project_root_directory = File.dirname(solution_file)
puts "(i) project_root_directory: #{project_root_directory}"

xcode_version = xcode_major_version!

# Preparing build params
builders = {
  'mdtool' => '/Applications/Xamarin Studio.app/Contents/MacOS/mdtool',
  'xbuild' => '/Library/Frameworks/Mono.framework/Versions/Current/bin/xbuild'
}

puts "\n=> generating .app"
params = ["\"#{builders[options[:builder]]}\""]
case options[:builder]
when 'xbuild'
  params << "/p:Configuration=\"#{options[:configuration]}\"" if options[:configuration]
  params << "/p:Platform=\"#{options[:platform]}\"" if options[:platform]
  params << "\"#{options[:solution]}\""
when 'mdtool'
  params << '-v build'
  params << "--configuration:\"#{options[:configuration]}|#{options[:platform]}\""
  params << "\"#{options[:solution]}\""
else
  fail_with_message('Invalid build tool detected')
end

# Building
puts "\n#{params.join(' ')}"
system("#{params.join(' ')}")
fail_with_message('Build failed') unless $?.success?
puts

build_path = Dir[File.join(project_root_directory, "/**/bin/#{options[:platform]}/#{options[:configuration]}")].first
fail_with_message('failed to get build path') unless build_path

app_path = export_app(build_path)
fail_with_message('failed to get .app path') unless app_path
puts "  (i) .app path: #{app_path}"

test_build_path = Dir[File.join(project_root_directory, "/**/*.UITests/bin/#{options[:configuration]}")].first
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
out, exit_code = run_unit_test(options[:nunit_path], dll_path)
fail_with_message("failed to run unit test, out:\n#{out}") if exit_code != 0
puts "(i) unit test successfully runned, output:\n"
puts "\n#{out}"

# Set output envs
work_dir = ENV['BITRISE_SOURCE_DIR']
result_log = File.join(work_dir, 'TestResult.xml')
`envman add --key BITRISE_XAMARIN_TEST_RESULT --value succeeded` if work_dir
`envman add --key BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT --value #{result_log}` if work_dir
