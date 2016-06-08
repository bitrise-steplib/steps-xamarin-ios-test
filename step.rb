require 'optparse'
require 'pathname'
require 'timeout'
require 'nokogiri'

require_relative 'xamarin-builder/builder'
require_relative 'xamarin-builder/common_constants'

# -----------------------
# --- Constants
# -----------------------

@mono = '/Library/Frameworks/Mono.framework/Versions/Current/bin/mono'

@work_dir = ENV['BITRISE_SOURCE_DIR']
@result_log_path = File.join(@work_dir, 'TestResult.xml')

# -----------------------
# --- Functions
# -----------------------

def log_info(message)
  puts
  puts "\e[34m#{message}\e[0m"
end

def log_details(message)
  puts "  #{message}"
end

def log_done(message)
  puts "  \e[32m#{message}\e[0m"
end

def log_warning(message)
  puts "\e[33m#{message}\e[0m"
end

def log_error(message)
  puts "\e[31m#{message}\e[0m"
end

def log_fail(message)
  system('envman add --key BITRISE_XAMARIN_TEST_RESULT --value failed')

  puts "\e[31m#{message}\e[0m"
  exit(1)
end

def to_bool(value)
  return true if value == true || value =~ (/^(true|t|yes|y|1)$/i)
  return false if value == false || value.nil? || value == '' || value =~ (/^(false|f|no|n|0)$/i)
  log_fail("Invalid value for Boolean: \"#{value}\"")
end

def simulator_udid_and_state(simulator_device, os_version)
  os_found = false
  os_regex = "-- #{os_version} --"
  os_separator_regex = '-- iOS \d.\d --'
  device_regex = simulator_device.to_s + '\s*\(([\w|-]*)\)\s*\(([\w]*)\)'

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

# -----------------------
# --- Main
# -----------------------

#
# Parse options
options = {
  project: nil,
  configuration: nil,
  platform: nil,
  test_to_run: nil,
  device: nil,
  os: nil
}

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: step.rb [options]'
  opts.on('-s', '--project path', 'Project path') { |s| options[:project] = s unless s.to_s == '' }
  opts.on('-c', '--configuration config', 'Configuration') { |c| options[:configuration] = c unless c.to_s == '' }
  opts.on('-p', '--platform platform', 'Platform') { |p| options[:platform] = p unless p.to_s == '' }
  opts.on('-t', '--test test', 'Test to run') { |t| options[:test_to_run] = t unless t.to_s == '' }
  opts.on('-d', '--device device', 'Device') { |d| options[:device] = d unless d.to_s == '' }
  opts.on('-o', '--os os', 'OS') { |o| options[:os] = o unless o.to_s == '' }
  opts.on('-h', '--help', 'Displays Help') do
    exit
  end
end
parser.parse!

#
# Print options
puts
puts '========== Configs =========='
puts " * project: #{options[:project]}"
puts " * configuration: #{options[:configuration]}"
puts " * platform: #{options[:platform]}"
puts " * test_to_run: #{options[:test_to_run]}"
puts " * simulator_device: #{options[:device]}"
puts " * simulator_os: #{options[:os]}"

#
# Validate options
log_fail('No project file found') unless options[:project] && File.exist?(options[:project])
log_fail('configuration not specified') unless options[:configuration]
log_fail('platform not specified') unless options[:platform]
log_fail('simulator_device not specified') unless options[:device]
log_fail('simulator_os_version not specified') unless options[:os]

udid, state = simulator_udid_and_state(options[:device], options[:os])
log_fail('failed to get simulator udid') unless udid || state

puts " * simulator_UDID: #{udid}"

#
# Main
nunit_path = ENV['NUNIT_PATH']
log_fail('No NUNIT_PATH environment specified') unless nunit_path

nunit_console_path = File.join(nunit_path, 'nunit3-console.exe')
log_fail('nunit3-console.exe not found') unless File.exist?(nunit_console_path)

builder = Builder.new(options[:project], options[:configuration], options[:platform],[Api::IOS])
begin
  builder.build
  builder.build_test
rescue => ex
  log_error(ex.inspect.to_s)
  log_error('--- Stack trace: ---')
  log_error(ex.backtrace.to_s)
  exit(1)
end

output = builder.generated_files
log_fail 'No output generated' if output.nil? || output.empty?

any_uitest_built = false

output.each do |_, project_output|
  api = project_output[:api]

  next unless api.eql? Api::IOS

  app = project_output[:app]
  uitests = project_output[:uitests]

  next if app.nil? || uitests.nil?

  ENV['APP_BUNDLE_PATH'] = File.expand_path(app)

  uitests.each do |dll_path|
    any_uitest_built = true

    puts
    log_info "Running UITest agains #{app}"

    params = [
      @mono,
      nunit_console_path,
      dll_path
    ]
    params << "--test=\"#{options[:test_to_run]}\"" unless options[:test_to_run].nil?

    command = params.join(' ')

    puts command
    success = system(command)

    #
    # Process output
    result_log = ''
    if File.exist? @result_log_path
      file = File.open(@result_log_path)
      result_log = file.read
      file.close

      system("envman add --key BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT --value \"#{result_log}\"") if result_log.to_s != ''
      log_details "Logs are available at path: #{@result_log_path}"
      puts
    end

    next if success

    doc = Nokogiri::XML(result_log)
    failed_tests = doc.xpath('//test-case[@result="Failed"]')

    if !failed_tests.empty?
      log_info 'Parsed TestResults.xml'

      failed_tests.each do |failed_test|
        puts
        log_error failed_test['name'].to_s
        log_error failed_test.xpath('./failure/message').text.to_s

        puts 'Stack trace:'
        puts failed_test.xpath('./failure/stack-trace').text
        puts
      end
    else
      puts
      puts result_log
      puts
    end

    log_fail('UITest execution failed')
  end

  # Set output envs
  system('envman add --key BITRISE_XAMARIN_TEST_RESULT --value succeeded')
  log_done 'UITests finished with success'

  system("envman add --key BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT --value #{@result_log_path}") if @result_log_path
  puts "Logs are available at: #{@result_log_path}"
end

unless any_uitest_built
  puts "generated_files: #{output}"
  log_fail 'No app or test dll found in outputs'
end
