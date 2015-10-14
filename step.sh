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
  "${xamarin_solution}" \
	"${xamarin_configuration}" \
	"${xamarin_platform}" \
	"${xamarin_builder}" \
  "${simulator_device}" \
	"${simulator_os_version}" \
	"${nunit_console_path}"
