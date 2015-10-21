#!/bin/bash

THIS_SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

set -e

if [ ! -z "${workdir}" ] ; then
	echo
	echo "=> Switching to working directory: ${workdir}"
	echo "$ cd ${workdir}"
	cd "${workdir}"
fi

echo
echo "==> Install nunit console"
echo
# Download nunit-console
NUNIT_DOWNLOAD_LINK="http://github.com/nunit/nunitv2/releases/download/2.6.4/NUnit-2.6.4.zip"
DOWNLOAD_DIR="${HOME}/.nunit"
DOWNLOAD_LOCATION="${DOWNLOAD_DIR}/NUnit-2.6.4.zip"

rm -rf "${DOWNLOAD_DIR}"
mkdir -p "${DOWNLOAD_DIR}"
curl -fL "${NUNIT_DOWNLOAD_LINK}" > "${DOWNLOAD_LOCATION}"

# Unzip nunit-console
UNZIP_LOCATION="${HOME}/.nunit"
unzip "${DOWNLOAD_LOCATION}" -d "${DOWNLOAD_DIR}"
rm -rf "${DOWNLOAD_LOCATION}"

# Export nunit-console path
NUNIT_CONSOLE="${UNZIP_LOCATION}/NUnit-2.6.4/bin/nunit-console.exe"

echo
echo "==> Performing step"
echo
ruby "${THIS_SCRIPTDIR}/step.rb" \
	-s "${xamarin_solution}" \
	-c "${xamarin_configuration}" \
	-p "${xamarin_platform}" \
	-b "${xamarin_builder}" \
	-d "${simulator_device}" \
	-o "${simulator_os_version}" \
	-n "${NUNIT_CONSOLE}"
