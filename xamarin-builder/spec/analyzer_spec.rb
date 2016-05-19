require_relative './../analyzer'
require_relative './../common_constants'

describe Analyzer do
  describe 'analyze' do
    it 'it raises exception if *.csproj path provided' do
      expect do
        project_path = './spec/fixtures/iOS/XamarinSampleApp.iOS.csproj'

        analyzer = Analyzer.new
        analyzer.analyze(project_path)
      end.to raise_error "Unsupported type detected"
    end

    it 'it raises exception if path to unknown file provided' do
      expect do
        file_path = './spec/fixtures/iOS/Main.cs'

        analyzer = Analyzer.new
        analyzer.analyze(file_path)
      end.to raise_error "unsupported type for path: ./spec/fixtures/iOS/Main.cs"
    end
  end

  describe 'inspect' do
    it 'it shows sln path and solution hash' do
      solution_path = './spec/fixtures/XamarinSampleApp.sln'

      analyzer = Analyzer.new
      analyzer.analyze(solution_path)

      expect(STDOUT).to receive(:puts).with('-- analyze: ./spec/fixtures/XamarinSampleApp.sln')
      expect(STDOUT).to receive(:puts).with(no_args)
      expect(STDOUT).to receive(:puts).with(any_args) # here we need to check that puts was invoked with some args

      analyzer.inspect
    end
  end

  describe 'build_solution_command' do
    before do
      solution_path = './spec/fixtures/XamarinSampleApp.sln'

      @analyzer = Analyzer.new
      @analyzer.analyze(solution_path)
    end

    it 'it generates valid mdtool build command' do
      command = @analyzer.build_solution_command('Release', 'iPhone')
      expect(command).to include(
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        "build",
        "\"-c:Release|iPhone\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\""
      )
    end
  end

  describe 'build_commands' do
    before do
      solution_path = './spec/fixtures/XamarinSampleApp.sln'

      @analyzer = Analyzer.new
      @analyzer.analyze(solution_path)
    end

    it 'it returns valid build commands for filter - iOS' do
      commands = @analyzer.build_commands('Release', 'iPhone', [Api::IOS])
      expect(commands.count).to eq(2)

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'build',
        "\"-c:Release|iPhone\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.iOS\""
      ])

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'archive',
        "\"-c:Release|iPhone\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.iOS\""
      ])
    end

    it 'it returns valid build commands for filter - iOS|Android' do
      commands = @analyzer.build_commands('Release', 'iPhone', [Api::IOS, Api::ANDROID])
      expect(commands.count).to eq(3)

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'build',
        "\"-c:Release|iPhone\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.iOS\""
      ])

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'archive',
        "\"-c:Release|iPhone\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.iOS\""
      ])

      expect(commands).to include([
        'xbuild',
        '/t:PackageForAndroid',
        '/p:Configuration="Release"',
        "\"./spec/fixtures/Droid/XamarinSampleApp.Droid.csproj\"",
        '/verbosity:minimal',
        '/nologo'
      ])
    end

    it 'it returns valid build commands for filter - Android|Mac' do
      commands = @analyzer.build_commands('Release', 'Any CPU', [Api::ANDROID, Api::MAC])
      expect(commands.count).to eq(3)

      expect(commands).to include([
        'xbuild',
        '/t:PackageForAndroid',
        '/p:Configuration="Release"',
        "\"./spec/fixtures/Droid/XamarinSampleApp.Droid.csproj\"",
        '/verbosity:minimal',
        '/nologo'
      ])

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'build',
        "\"-c:Release|iPhoneSimulator\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.Mac\""
      ])

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'archive',
        "\"-c:Release|iPhoneSimulator\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.Mac\""
      ])
    end

    it 'it returns valid build commands for filter - iOS|Mac' do
      commands = @analyzer.build_commands('Release', 'Any CPU', [Api::IOS, Api::MAC])
      expect(commands.count).to eq(4)

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'build',
        "\"-c:Release|iPhoneSimulator\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.Mac\""
      ])

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'archive',
        "\"-c:Release|iPhoneSimulator\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.Mac\""
      ])

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'build',
        "\"-c:Release|iPhone\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.iOS\""
      ])

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'archive',
        "\"-c:Release|iPhone\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.iOS\""
      ])
    end

    it 'it returns valid build commands for default filter - iOS|Mac|Android' do
      commands = @analyzer.build_commands('Release', 'Any CPU', [Api::IOS, Api::ANDROID, Api::MAC])
      expect(commands.count).to eq(5)

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'build',
        "\"-c:Release|iPhoneSimulator\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.Mac\""
      ])

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'archive',
        "\"-c:Release|iPhoneSimulator\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.Mac\""
      ])

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'build',
        "\"-c:Release|iPhone\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.iOS\""
      ])

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'archive',
        "\"-c:Release|iPhone\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.iOS\""
      ])

      expect(commands).to include([
        'xbuild',
        '/t:PackageForAndroid',
        '/p:Configuration="Release"',
        "\"./spec/fixtures/Droid/XamarinSampleApp.Droid.csproj\"",
        '/verbosity:minimal',
        '/nologo'
      ])
    end

    it 'it returns valid build commands when id_filters specified' do
      ios_project_guid = '{8B618FBA-3179-42BF-856D-0F9CC190A735}'
      commands = @analyzer.build_commands('Release', 'Any CPU', [Api::IOS, Api::ANDROID, Api::MAC], ios_project_guid)
      expect(commands.count).to eq(2)

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'build',
        "\"-c:Release|iPhone\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.iOS\""
      ])

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'archive',
        "\"-c:Release|iPhone\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.iOS\""
      ])
    end
  end

  describe 'build_test_commands' do
    it 'it returns valid build command for Xamarin.UITest project' do
      solution_path = './spec/fixtures/XamarinSampleApp.sln'

      @analyzer = Analyzer.new
      @analyzer.analyze(solution_path)

      commands, = @analyzer.build_test_commands('Release', 'Any CPU', [Api::IOS, Api::ANDROID])
      expect(commands.count).to eq(4)

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'build',
        "\"-c:Release|iPhone\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.iOS\""
      ])

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'archive',
        "\"-c:Release|iPhone\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.iOS\""
      ])

      expect(commands).to include([
        'xbuild',
        '/t:PackageForAndroid',
        '/p:Configuration="Release"',
        "\"./spec/fixtures/Droid/XamarinSampleApp.Droid.csproj\"",
        '/verbosity:minimal',
        '/nologo'
      ])

      expect(commands).to include([
        "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\"",
        'build',
        "\"-c:Release\"",
        "\"./spec/fixtures/XamarinSampleApp.sln\"",
        "\"-p:XamarinSampleApp.UITests\""
      ])
    end
  end

  describe 'nunit_test_commands' do
  end
end
