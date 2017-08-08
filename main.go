package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/bitrise-io/go-utils/fileutil"
	"github.com/bitrise-io/go-utils/log"
	"github.com/bitrise-io/go-utils/pathutil"
	"github.com/bitrise-tools/go-steputils/input"
	"github.com/bitrise-tools/go-steputils/tools"
	"github.com/bitrise-tools/go-xamarin/builder"
	"github.com/bitrise-tools/go-xamarin/constants"
	"github.com/bitrise-tools/go-xamarin/tools/buildtools"
	"github.com/bitrise-tools/go-xamarin/tools/nunit"
	"github.com/bitrise-tools/go-xcode/simulator"
	"github.com/hashicorp/go-version"
)

// ConfigsModel ...
type ConfigsModel struct {
	SimulatorDevice    string
	SimulatorOsVersion string
	TestToRun          string

	XamarinSolution      string
	XamarinConfiguration string
	XamarinPlatform      string

	BuildTool string
	DeployDir string
}

func createConfigsModelFromEnvs() ConfigsModel {
	return ConfigsModel{
		SimulatorDevice:    os.Getenv("simulator_device"),
		SimulatorOsVersion: os.Getenv("simulator_os_version"),
		TestToRun:          os.Getenv("test_to_run"),

		XamarinSolution:      os.Getenv("xamarin_project"),
		XamarinConfiguration: os.Getenv("xamarin_configuration"),
		XamarinPlatform:      os.Getenv("xamarin_platform"),

		BuildTool: os.Getenv("build_tool"),
		DeployDir: os.Getenv("BITRISE_DEPLOY_DIR"),
	}
}

func (configs ConfigsModel) print() {
	log.Infof("Testing:")

	log.Printf("- SimulatorDevice: %s", configs.SimulatorDevice)
	log.Printf("- SimulatorOsVersion: %s", configs.SimulatorOsVersion)
	log.Printf("- TestToRun: %s", configs.TestToRun)

	log.Infof("Configs:")

	log.Printf("- XamarinSolution: %s", configs.XamarinSolution)
	log.Printf("- XamarinConfiguration: %s", configs.XamarinConfiguration)
	log.Printf("- XamarinPlatform: %s", configs.XamarinPlatform)

	log.Infof("Debug:")

	log.Printf("- BuildTool: %s", configs.BuildTool)
	log.Printf("- DeployDir: %s", configs.DeployDir)
}

func (configs ConfigsModel) validate() error {
	if err := input.ValidateIfNotEmpty(configs.SimulatorDevice); err != nil {
		return fmt.Errorf("SimulatorDevice - %s", err)
	}
	if err := input.ValidateIfNotEmpty(configs.SimulatorOsVersion); err != nil {
		return fmt.Errorf("SimulatorOsVersion - %s", err)
	}

	if err := input.ValidateIfPathExists(configs.XamarinSolution); err != nil {
		return fmt.Errorf("XamarinSolution - %s", err)
	}
	if err := input.ValidateIfNotEmpty(configs.XamarinConfiguration); err != nil {
		return fmt.Errorf("XamarinConfiguration - %s", err)
	}
	if err := input.ValidateIfNotEmpty(configs.XamarinPlatform); err != nil {
		return fmt.Errorf("XamarinPlatform - %s", err)
	}

	if err := input.ValidateWithOptions(configs.BuildTool, "msbuild", "xbuild"); err != nil {
		return fmt.Errorf("BuildTool - %s", err)
	}

	return nil
}

func getLatestIOSVersion(osVersionSimulatorInfosMap simulator.OsVersionSimulatorInfosMap) (string, error) {
	var latestVersionPtr *version.Version
	for osVersion := range osVersionSimulatorInfosMap {
		if !strings.HasPrefix(osVersion, "iOS") {
			continue
		}

		versionStr := strings.TrimPrefix(osVersion, "iOS")
		versionStr = strings.TrimSpace(versionStr)

		versionPtr, err := version.NewVersion(versionStr)
		if err != nil {
			return "", fmt.Errorf("Failed to parse version (%s), error: %s", versionStr, err)
		}

		if latestVersionPtr == nil || versionPtr.GreaterThan(latestVersionPtr) {
			latestVersionPtr = versionPtr
		}
	}

	if latestVersionPtr == nil {
		return "", fmt.Errorf("Failed to determin latest iOS simulator version")
	}

	versionSegments := latestVersionPtr.Segments()
	if len(versionSegments) < 2 {
		return "", fmt.Errorf("Invalid version created: %s, segments count < 2", latestVersionPtr.String())
	}

	return fmt.Sprintf("iOS %d.%d", versionSegments[0], versionSegments[1]), nil
}

func getSimulatorInfo(osVersion, deviceName string) (simulator.InfoModel, error) {
	osVersionSimulatorInfosMap, err := simulator.GetOsVersionSimulatorInfosMap()
	if err != nil {
		return simulator.InfoModel{}, err
	}

	if osVersion == "latest" {
		latestOSVersion, err := getLatestIOSVersion(osVersionSimulatorInfosMap)
		if err != nil {
			return simulator.InfoModel{}, err
		}
		osVersion = latestOSVersion
	}

	infos, ok := osVersionSimulatorInfosMap[osVersion]
	if !ok {
		return simulator.InfoModel{}, fmt.Errorf("No simulators found for os version: %s", osVersion)
	}

	for _, info := range infos {
		if info.Name == deviceName {
			return info, nil
		}
	}

	return simulator.InfoModel{}, fmt.Errorf("No simulators found for os version: (%s), device name: (%s)", osVersion, deviceName)
}

func testResultLogContent(pth string) (string, error) {
	if exist, err := pathutil.IsPathExists(pth); err != nil {
		return "", fmt.Errorf("Failed to check if path (%s) exist, error: %s", pth, err)
	} else if !exist {
		return "", fmt.Errorf("test result not exist at: %s", pth)
	}

	content, err := fileutil.ReadStringFromFile(pth)
	if err != nil {
		return "", fmt.Errorf("Failed to read file (%s), error: %s", pth, err)
	}

	return content, nil
}

func parseErrorFromResultLog(content string) (string, error) {
	failureLineFound := false
	lastFailureMessage := ""

	scanner := bufio.NewScanner(strings.NewReader(content))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		if line == "<failure>" {
			failureLineFound = true
			continue
		}

		if failureLineFound && strings.HasPrefix(line, "<message>") {
			lastFailureMessage = line
		}

		failureLineFound = false
	}

	return lastFailureMessage, nil
}

func failf(format string, v ...interface{}) {
	log.Errorf(format, v...)
	if err := tools.ExportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_RESULT", "failed"); err != nil {
		log.Warnf("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_RESULT", err)
	}
	os.Exit(1)
}

func main() {
	configs := createConfigsModelFromEnvs()

	fmt.Println()
	configs.print()

	if err := configs.validate(); err != nil {
		failf("Issue with input: %s", err)
	}

	// Get Simulator Infos
	fmt.Println()
	log.Infof("Collecting simulator info...")
	simulatorInfo, err := getSimulatorInfo(configs.SimulatorOsVersion, configs.SimulatorDevice)
	if err != nil {
		failf("Failed to get simulator infos, error: %s", err)
	}
	log.Donef("Simulator (%s), id: (%s), status: %s", simulatorInfo.Name, simulatorInfo.ID, simulatorInfo.Status)

	if err := os.Setenv("IOS_SIMULATOR_UDID", simulatorInfo.ID); err != nil {
		failf("Failed to export simulator UDID, error: %s", err)
	}

	// ---

	// Nunit Console path
	nunitConsolePth, err := nunit.SystemNunit3ConsolePath()
	if err != nil {
		failf("Failed to get system insatlled nunit3-console.exe path, error: %s", err)
	}
	// ---

	//
	// build
	fmt.Println()
	log.Infof("Building all iOS Xamarin UITest and Referred Projects in solution: %s", configs.XamarinSolution)

	buildTool := buildtools.Xbuild
	if configs.BuildTool == "msbuild" {
		buildTool = buildtools.Msbuild
	}

	builder, err := builder.New(configs.XamarinSolution, []constants.SDK{constants.SDKIOS}, buildTool)
	if err != nil {
		failf("Failed to create xamarin builder, error: %s", err)
	}

	callback := func(solutionName string, projectName string, sdk constants.SDK, testFramework constants.TestFramework, commandStr string, alreadyPerformed bool) {
		fmt.Println()
		if testFramework == constants.TestFrameworkXamarinUITest {
			log.Infof("Building test project: %s", projectName)
		} else {
			log.Infof("Building project: %s", projectName)
		}

		log.Donef("$ %s", commandStr)

		if alreadyPerformed {
			log.Warnf("build command already performed, skipping...")
		}

		fmt.Println()
	}

	startTime := time.Now()
	warnings, err := builder.BuildAndRunAllXamarinUITestAndReferredProjects(configs.XamarinConfiguration, configs.XamarinPlatform, nil, callback)
	endTime := time.Now()

	for _, warning := range warnings {
		log.Warnf(warning)
	}
	if err != nil {
		failf("Build failed, error: %s", err)
	}

	projectOutputMap, err := builder.CollectProjectOutputs(configs.XamarinConfiguration, configs.XamarinPlatform, startTime, endTime)
	if err != nil {
		failf("Failed to collect project outputs, error: %s", err)
	}

	testProjectOutputMap, warnings, err := builder.CollectXamarinUITestProjectOutputs(configs.XamarinConfiguration, configs.XamarinPlatform, startTime, endTime)
	for _, warning := range warnings {
		log.Warnf(warning)
	}
	if err != nil {
		failf("Failed to collect test project output, error: %s", err)
	}
	if len(testProjectOutputMap) == 0 {
		failf("No testable output generated")
	}
	// ---

	//
	// Run nunit tests
	nunitConsole, err := nunit.New(nunitConsolePth)
	if err != nil {
		failf("Failed to create nunit console model, error: %s", err)
	}

	resultLogPth := filepath.Join(configs.DeployDir, "TestResult.xml")
	nunitConsole.SetResultLogPth(resultLogPth)

	// Artifacts
	resultLog := ""

	for testProjectName, testProjectOutput := range testProjectOutputMap {
		if len(testProjectOutput.ReferredProjectNames) == 0 {
			log.Warnf("Test project (%s) does not refers to any project, skipping...", testProjectName)
			continue
		}

		for _, projectName := range testProjectOutput.ReferredProjectNames {
			projectOutput, ok := projectOutputMap[projectName]
			if !ok {
				continue
			}

			appPth := ""
			for _, output := range projectOutput.Outputs {
				if output.OutputType == constants.OutputTypeAPP {
					appPth = output.Pth
				}
			}

			if appPth == "" {
				failf("No app generated for project: %s", projectName)
			}

			// Set APP_BUNDLE_PATH env to let the test know which .app file should be tested
			// This env is used in the Xamarin.UITest project to refer to the .app path
			if err := os.Setenv("APP_BUNDLE_PATH", appPth); err != nil {
				failf("Failed to set APP_BUNDLE_PATH environment, without this env test will fail, error: %s", err)
			}

			// Run test
			fmt.Println()
			log.Infof("Testing (%s) against (%s)", testProjectName, projectName)
			log.Printf("test dll: %s", testProjectOutput.Output.Pth)
			log.Printf("app: %s", appPth)

			nunitConsole.SetDLLPth(testProjectOutput.Output.Pth)
			nunitConsole.SetTestToRun(configs.TestToRun)

			fmt.Println()
			log.Infof("Running Xamarin UITest")
			log.Donef("$ %s", nunitConsole.PrintableCommand())
			fmt.Println()

			err := nunitConsole.Run()
			testLog, readErr := testResultLogContent(resultLogPth)
			if readErr != nil {
				log.Warnf("Failed to read test result, error: %s", readErr)
			}
			resultLog = testLog

			if err != nil {
				if errorMsg, err := parseErrorFromResultLog(resultLog); err != nil {
					log.Warnf("Failed to parse error message from result log, error: %s", err)
				} else if errorMsg != "" {
					log.Errorf("%s", errorMsg)
				}

				if resultLog != "" {
					if err := tools.ExportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT", resultLog); err != nil {
						log.Warnf("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT", err)
					}
				}

				failf("Test failed, error: %s", err)
			}
		}
	}

	if err := tools.ExportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_RESULT", "succeeded"); err != nil {
		log.Warnf("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_RESULT", err)
	}

	if resultLog != "" {
		if err := tools.ExportEnvironmentWithEnvman("BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT", resultLog); err != nil {
			log.Warnf("Failed to export environment: %s, error: %s", "BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT", err)
		}
	}
}
