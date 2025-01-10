#!/bin/bash
set -eu

cd "$( dirname "$0" )/.."

declare kernelSpecsDir='./venv/share/jupyter/kernels'
declare kernelProxyCmdName='kernel_proxy_ipc2tcp.sh'
declare jqVersion='1.7.1'

declare wrappedTcpKernel="$1" newProxyKernelName="${2:-"${1}_ipc2tcp_proxy"}"
declare jupyterCmd; jupyterCmd="$( which 'jupyter' )"
declare arch="linux-$( uname -m | sed 's/aarch64/arm64/' | sed 's/x86_64/amd64/' )"
declare -p wrappedTcpKernel newProxyKernelName jupyterCmd arch


function downloadJq() {
  local downloadDir="$1" jqVersion="$2" arch="$3"
  if ! "${downloadDir}/jq" --version >'/dev/null' 2>&1; then
    set -x
    mkdir -p "${downloadDir}"
    wget --backups "https://github.com/jqlang/jq/releases/download/jq-${jqVersion}/jq-${arch}" -O "${downloadDir}/jq"
    chmod +x "${downloadDir}/jq"
    set +x
  fi
}


function createKernelSpecDir() {
  local kernelDir="$1"
  mkdir -p "${kernelDir}"
  cp -f "./src/${kernelProxyCmdName}" "${kernelDir}/"
  chmod +x "${kernelDir}/${kernelProxyCmdName}"
}



### MAIN

declare kernelDir; kernelDir="$( readlink -f "${kernelSpecsDir}/${newProxyKernelName}" )"

createKernelSpecDir "${kernelDir}"
downloadJq "${kernelDir}" "${jqVersion}" "${arch}"

# create connection file using wrapped kernel connection file as template
# shellcheck disable=SC2016
"${kernelDir}"/jq \
  '.argv=$ARGS.positional | .name=$kernelName | .display_name+=$displayNameSuffix' \
  --arg 'displayNameSuffix' ' (ipc2tcp_proxy)' \
  --arg 'kernelName' "${newProxyKernelName}" \
  --args "${kernelDir}/${kernelProxyCmdName}" "${wrappedTcpKernel}" '{connection_file}' "${jupyterCmd}" \
  < "${kernelSpecsDir}/${wrappedTcpKernel}/kernel.json" \
  > "${kernelDir}/kernel.json"
