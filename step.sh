#!/bin/bash

THIS_SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

set -e

ruby "${THIS_SCRIPTDIR}/step.rb" \
	-s "${xamarin_project}" \
	-t "${xamarin_test_project}" \
	-c "${xamarin_configuration}" \
	-p "${xamarin_platform}" \
	-b "${xamarin_builder}" \
	-i "${is_clean_build}" \
	-d "${simulator_device}" \
	-o "${simulator_os_version}"
