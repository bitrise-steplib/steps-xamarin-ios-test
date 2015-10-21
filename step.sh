#!/bin/bash

THIS_SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

set -e

if [ ! -z "${workdir}" ] ; then
	echo
	echo "=> Switching to working directory: ${workdir}"
	echo "$ cd ${workdir}"
	cd "${workdir}"
fi

ruby "${THIS_SCRIPTDIR}/step.rb" \
	-s "${xamarin_solution}" \
	-c "${xamarin_configuration}" \
	-p "${xamarin_platform}" \
	-b "${xamarin_builder}" \
	-d "${simulator_device}" \
	-o "${simulator_os_version}" \
	-n "${nunit_console_path}"
