package mdtool

import (
	"fmt"
	"time"

	"github.com/bitrise-io/go-utils/cmdex"
	"github.com/bitrise-io/go-utils/pathutil"
	"github.com/bitrise-tools/go-xamarin/constants"
)

const (
	diagnosticModeWaitTime      = 300 * time.Second
	diagnosticModeForceWaitTime = 60 * time.Second
)

// Model ...
type Model struct {
	buildTool string

	solutionPth string
	projectName string

	configuration string
	platform      string
	target        string

	customOptions []string
}

// New ...
func New(solutionPth string) (*Model, error) {
	absSolutionPth, err := pathutil.AbsPath(solutionPth)
	if err != nil {
		return nil, fmt.Errorf("Failed to expand path (%s), error: %s", solutionPth, err)
	}

	return &Model{solutionPth: absSolutionPth, buildTool: constants.MDToolPath}, nil
}

// SetTarget ...
func (mdtool *Model) SetTarget(target string) *Model {
	mdtool.target = target
	return mdtool
}

// SetConfiguration ...
func (mdtool *Model) SetConfiguration(configuration string) *Model {
	mdtool.configuration = configuration
	return mdtool
}

// SetPlatform ...
func (mdtool *Model) SetPlatform(platform string) *Model {
	mdtool.platform = platform
	return mdtool
}

// SetProjectName ...
func (mdtool *Model) SetProjectName(projectName string) *Model {
	mdtool.projectName = projectName
	return mdtool
}

// SetCustomOptions ...
func (mdtool *Model) SetCustomOptions(options ...string) {
	mdtool.customOptions = options
}

func (mdtool Model) buildCommandSlice() []string {
	cmdSlice := []string{mdtool.buildTool}

	if mdtool.target != "" {
		cmdSlice = append(cmdSlice, mdtool.target)
	}

	if mdtool.solutionPth != "" {
		cmdSlice = append(cmdSlice, mdtool.solutionPth)
	}

	config := ""
	if mdtool.configuration != "" {
		config = mdtool.configuration
	}

	if mdtool.platform != "" && mdtool.platform != "Any CPU" && mdtool.platform != "AnyCPU" {
		config += "|" + mdtool.platform
	}

	if config != "" {
		cmdSlice = append(cmdSlice, fmt.Sprintf("-c:%s", config))
	}

	if mdtool.projectName != "" {
		cmdSlice = append(cmdSlice, fmt.Sprintf("-p:%s", mdtool.projectName))
	}

	cmdSlice = append(cmdSlice, mdtool.customOptions...)

	return cmdSlice
}

// PrintableCommand ...
func (mdtool Model) PrintableCommand() string {
	cmdSlice := mdtool.buildCommandSlice()

	return cmdex.PrintableCommandArgs(true, cmdSlice)
}

// Run ...
func (mdtool Model) Run() error {
	cmdSlice := mdtool.buildCommandSlice()

	command, err := cmdex.NewCommandFromSlice(cmdSlice)
	if err != nil {
		return err
	}

	/*
		command.SetStdout(os.Stdout)
		command.SetStderr(os.Stderr)

		return command.Run()
	*/

	return runCommandInDiagnosticMode(*command, "Loading projects", diagnosticModeWaitTime, diagnosticModeForceWaitTime, true)
}
