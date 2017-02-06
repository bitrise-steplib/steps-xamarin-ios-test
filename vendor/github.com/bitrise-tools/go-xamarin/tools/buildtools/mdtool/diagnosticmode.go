package mdtool

import (
	"bufio"
	"fmt"
	"strings"
	"syscall"
	"time"

	"github.com/bitrise-io/go-utils/command"
	"github.com/bitrise-io/go-utils/log"
)

func runCommandInDiagnosticMode(command command.Model, checkPattern string, waitTime time.Duration, forceWaitTime time.Duration, retryOnHang bool) error {
	log.Warnf("Run in diagnostic mode")

	// copy command model to avoid re-run error: Stdout already set
	cmd := *command.GetCmd()

	timeout := false

	// Create a timer that will FORCE kill the process if normal kill does not work
	var forceKillError error
	var forceKillTimeoutHandler *time.Timer
	startForceKillTimeoutHandler := func() {
		forceKillTimeoutHandler = time.AfterFunc(forceWaitTime, func() {
			log.Warnf("Process QUIT timeout")

			forceKillError = cmd.Process.Signal(syscall.SIGKILL)
		})
	}
	// ----

	// Create a timer that will kill the process
	var killError error
	var killTimeoutHandler *time.Timer
	startKillTimeoutHandler := func() {
		killTimeoutHandler = time.AfterFunc(waitTime, func() {
			log.Warnf("Process timed out")

			timeout = true

			killError = cmd.Process.Signal(syscall.SIGQUIT)

			startForceKillTimeoutHandler()
		})
	}

	// ----

	// Redirect output
	stdoutReader, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}

	scanner := bufio.NewScanner(stdoutReader)
	go func() {
		for scanner.Scan() {
			line := scanner.Text()
			fmt.Println(line)

			// stop timeout handler if new line comes
			if killTimeoutHandler != nil {
				killTimeoutHandler.Stop()
			}

			// if line contains check pattern start hang timeout handler
			if strings.Contains(strings.TrimSpace(line), checkPattern) {
				startKillTimeoutHandler()
			}
		}
	}()
	if err := scanner.Err(); err != nil {
		return err
	}
	// ----

	if err := cmd.Start(); err != nil {
		return err
	}

	// Only proceed once the process has finished
	cmdErr := cmd.Wait()

	if killTimeoutHandler != nil {
		killTimeoutHandler.Stop()
	}

	if forceKillTimeoutHandler != nil {
		forceKillTimeoutHandler.Stop()
	}

	if cmdErr != nil {
		if !timeout || cmdErr.Error() != "signal: killed" {
			return cmdErr
		}
	}

	if killError != nil {
		return killError
	}
	if forceKillError != nil {
		return forceKillError
	}

	if timeout {
		if retryOnHang {
			return runCommandInDiagnosticMode(command, checkPattern, waitTime, forceWaitTime, false)
		}
		return fmt.Errorf("timed out")
	}

	return nil
	// ----
}
