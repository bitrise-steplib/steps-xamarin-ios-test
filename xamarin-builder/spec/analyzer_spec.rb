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

  describe 'ios_project_type' do
    it 'it returns true for Xamarin.iOS project types' do
      xamarin_ios_project_type_guids = [
        'E613F3A2-FE9C-494F-B74E-F63BCB86FEA6',
        '6BC8ED88-2882-458C-8E55-DFD12B67127B',
        'F5B4F3BC-B597-4E2B-B552-EF5D8A32436F',
        'FEACFBD2-3405-455C-9665-78FE426C6842',
        '8FFB629D-F513-41CE-95D2-7ECE97B6EEEC',
        'EE2C853D-36AF-4FDB-B1AD-8E90477E2198'
      ]

      analyzer = Analyzer.new

      xamarin_ios_project_type_guids.each do |guid|
        expect(analyzer.ios_project_type?(guid)).to eq(true)
      end
    end

    it 'it returns false if not contains Xamarin.iOS project types' do
      xamarin_android_project_type_guids = [
        'EFBA0AD7-5A72-4C68-AF49-83D382785DCF'
      ]

      analyzer = Analyzer.new

      xamarin_android_project_type_guids.each do |guid|
        expect(analyzer.ios_project_type?(guid)).to eq(false)
      end
    end
  end

  describe 'mac_project_type' do
    it 'it returns true for MonoMac and Xamarin.Mac project types' do
      mac_project_type_guids = [
        '1C533B1C-72DD-4CB1-9F6B-BF11D93BCFBE',
        '42C0BBD9-55CE-4FC1-8D90-A7348ABAFB23'
      ]

      analyzer = Analyzer.new

      mac_project_type_guids.each do |guid|
        expect(analyzer.mac_project_type?(guid)).to eq(true)
      end
    end

    describe 'identify_project_api' do
      it 'it returns Api::IOS for Xamarin.iOS project types' do
        project_type_guids = [
          '{E613F3A2-FE9C-494F-B74E-F63BCB86FEA6}'
        ]

        analyzer = Analyzer.new

        project_type_guids.each do |guid|
          expect(analyzer.identify_project_api(guid)).to eq(Api::IOS)
        end
      end

      it 'it returns Api::ANDROID for Xamarin.Android project types' do
        project_type_guids = [
          '{10368E6C-D01B-4462-8E8B-01FC667A7035};{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}'
        ]

        analyzer = Analyzer.new

        project_type_guids.each do |guid|
          expect(analyzer.identify_project_api(guid)).to eq(Api::ANDROID)
        end
      end

      it 'it returns Api::MAC for MonoMac and Xamarin.Mac project types' do
        project_type_guids = [
          '{1C533B1C-72DD-4CB1-9F6B-BF11D93BCFBE};{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}',
          '{42C0BBD9-55CE-4FC1-8D90-A7348ABAFB23};{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}'
        ]

        analyzer = Analyzer.new

        project_type_guids.each do |guid|
          expect(analyzer.identify_project_api(guid)).to eq(Api::MAC)
        end
      end

      it 'it returns Api::TVOS for Xamarin.tvOS project types' do
        project_type_guids = [
          '{06FA79CB-D6CD-4721-BB4B-1BD202089C55}'
        ]

        analyzer = Analyzer.new

        project_type_guids.each do |guid|
          expect(analyzer.identify_project_api(guid)).to eq(Api::TVOS)
        end
      end

      it 'it returns Api::UNKNOWN for unknown project types' do
        project_type_guids = [
          '{06FA79CB-D6CD-4721-BB4B}'
        ]

        analyzer = Analyzer.new

        project_type_guids.each do |guid|
          expect(analyzer.identify_project_api(guid)).to eq(Api::UNKNOWN)
        end
      end
    end
  end
end
