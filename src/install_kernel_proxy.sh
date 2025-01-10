#!/bin/bash
set -eu

cd "$( dirname "$0" )/.."

declare kernelSpecsSubDir='share/jupyter/kernels'
declare kernelProxyCmdName='kernel_proxy_ipc2tcp.sh'
declare jqVersion='1.7.1'

declare wrappedTcpKernel="$1" newProxyKernelName="${2:-"${1}_ipc2tcp_proxy"}"
declare -p wrappedTcpKernel newProxyKernelName

declare jupyterCmd; jupyterCmd="$( which 'jupyter' )"
declare sysPrefix; sysPrefix="$( python -c 'import sys; print (sys.prefix)' )"
declare arch; arch="linux-$( uname -m | sed 's/aarch64/arm64/' | sed 's/x86_64/amd64/' )"
declare -p jupyterCmd sysPrefix arch


function downloadJq() {
  local downloadDir="$1" jqVersion="$2" arch="$3"
  if ! "${downloadDir}/jq" --version >'/dev/null' 2>&1; then
    { set -x
      mkdir -p "${downloadDir}"
      wget --backups --progress='bar:force:noscroll' -O "${downloadDir}/jq" \
        "https://github.com/jqlang/jq/releases/download/jq-${jqVersion}/jq-${arch}"
      chmod +x "${downloadDir}/jq"
    }
  fi
}


function createKernelSpecDir() {
  local kernelDir="$1"
  mkdir -p "${kernelDir}"
  cp -f "./src/${kernelProxyCmdName}" "${kernelDir}/"
  chmod +x "${kernelDir}/${kernelProxyCmdName}"
}



### MAIN

declare kernelSpecDirPath="${sysPrefix}/${kernelSpecsSubDir}/${newProxyKernelName}"

createKernelSpecDir "${kernelSpecDirPath}"
downloadJq "${kernelSpecDirPath}" "${jqVersion}" "${arch}"

# create connection file using wrapped kernel connection file as template
# shellcheck disable=SC2016
"${sysPrefix}/${kernelSpecsSubDir}/${newProxyKernelName}"/jq \
  '.argv=$ARGS.positional | .name=$kernelName | .display_name+=$displayNameSuffix' \
  --arg 'displayNameSuffix' ' (ipc2tcp_proxy)' \
  --arg 'kernelName' "${newProxyKernelName}" \
  --args "{prefix}/${kernelSpecsSubDir}/${newProxyKernelName}/${kernelProxyCmdName}" "${wrappedTcpKernel}" '{connection_file}' "${jupyterCmd}" \
  < "${sysPrefix}/${kernelSpecsSubDir}/${wrappedTcpKernel}/kernel.json" \
  > "${kernelSpecDirPath}/kernel.json"
