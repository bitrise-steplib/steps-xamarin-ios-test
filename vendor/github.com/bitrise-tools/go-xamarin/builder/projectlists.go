package builder

import (
	"fmt"

	"github.com/bitrise-tools/go-xamarin/analyzers/project"
	"github.com/bitrise-tools/go-xamarin/constants"
	"github.com/bitrise-tools/go-xamarin/utility"
)

func (builder Model) whitelistedProjects() []project.Model {
	projects := []project.Model{}

	for _, proj := range builder.solution.ProjectMap {
		if !whitelistAllows(proj.ProjectType, builder.projectTypeWhitelist...) {
			continue
		}

		if proj.ProjectType != constants.ProjectTypeUnknown {
			projects = append(projects, proj)
		}
	}

	return projects
}

func (builder Model) buildableProjects(configuration, platform string) ([]project.Model, []string) {
	projects := []project.Model{}
	warnings := []string{}

	solutionConfig := utility.ToConfig(configuration, platform)

	whitelistedProjects := builder.whitelistedProjects()

	for _, proj := range whitelistedProjects {
		//
		// Solution config - project config mapping
		_, ok := proj.ConfigMap[solutionConfig]
		if !ok {
			warnings = append(warnings, fmt.Sprintf("project (%s) do not have config for solution config (%s), skipping...", proj.Name, solutionConfig))
			continue
		}

		if (proj.ProjectType == constants.ProjectTypeIOS ||
			proj.ProjectType == constants.ProjectTypeMacOS ||
			proj.ProjectType == constants.ProjectTypeTvOS) &&
			proj.OutputType != "exe" {
			warnings = append(warnings, fmt.Sprintf("project (%s) does not archivable based on output type (%s), skipping...", proj.Name, proj.OutputType))
			continue
		}
		if proj.ProjectType == constants.ProjectTypeAndroid &&
			!proj.AndroidApplication {
			warnings = append(warnings, fmt.Sprintf("(%s) is not an android application project, skipping...", proj.Name))
			continue
		}

		if proj.ProjectType != constants.ProjectTypeUnknown {
			projects = append(projects, proj)
		}
	}

	return projects, warnings
}

func (builder Model) buildableXamarinUITestProjectsAndReferredProjects(configuration, platform string) ([]project.Model, []project.Model, []string) {
	testProjects := []project.Model{}
	referredProjects := []project.Model{}

	warnings := []string{}

	solutionConfig := utility.ToConfig(configuration, platform)

	for _, proj := range builder.solution.ProjectMap {
		// Check if is XamarinUITest project
		if proj.ProjectType != constants.ProjectTypeXamarinUITest {
			continue
		}

		// Check if contains config mapping
		_, ok := proj.ConfigMap[solutionConfig]
		if !ok {
			warnings = append(warnings, fmt.Sprintf("project (%s) do not have config for solution config (%s), skipping...", proj.Name, solutionConfig))
			continue
		}

		// Collect referred projects
		if len(proj.ReferredProjectIDs) == 0 {
			warnings = append(warnings, fmt.Sprintf("no referred projects found for test project: %s, skipping...", proj.Name))
			continue
		}

		for _, projectID := range proj.ReferredProjectIDs {
			referredProj, ok := builder.solution.ProjectMap[projectID]
			if !ok {
				warnings = append(warnings, fmt.Sprintf("project reference exist with project id: %s, but project not found in solution", projectID))
				continue
			}

			if referredProj.ProjectType == constants.ProjectTypeUnknown {
				warnings = append(warnings, fmt.Sprintf("project's (%s) project type is unkown", referredProj.Name))
				continue
			}

			if whitelistAllows(referredProj.ProjectType, builder.projectTypeWhitelist...) {
				referredProjects = append(referredProjects, referredProj)
			}
		}

		if len(referredProjects) == 0 {
			warnings = append(warnings, fmt.Sprintf("test project (%s) does not refers to any project, with project type whitelist (%v), skipping...", proj.Name, builder.projectTypeWhitelist))
			continue
		}

		testProjects = append(testProjects, proj)
	}

	return testProjects, referredProjects, warnings
}

func (builder Model) buildableNunitTestProjects(configuration, platform string) ([]project.Model, []string) {
	testProjects := []project.Model{}

	warnings := []string{}

	solutionConfig := utility.ToConfig(configuration, platform)

	for _, proj := range builder.solution.ProjectMap {
		// Check if is nunit test project
		if proj.ProjectType != constants.ProjectTypeNunitTest {
			continue
		}

		// Check if contains config mapping
		_, ok := proj.ConfigMap[solutionConfig]
		if !ok {
			warnings = append(warnings, fmt.Sprintf("project (%s) do not have config for solution config (%s), skipping...", proj.Name, solutionConfig))
			continue
		}

		testProjects = append(testProjects, proj)
	}

	return testProjects, warnings
}
