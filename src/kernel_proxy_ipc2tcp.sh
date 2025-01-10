#!/bin/bash
set -eum

declare kernelRuntimeDir="${HOME}/.local/share/jupyter/runtime"
declare -i tcpKernelConnFileTimeout=5

declare wrappedTcpKernel="${1?}" connFile="${2?}" jupyterCmd="${3?}"
declare -p connFile wrappedTcpKernel jupyterCmd


function startWrappedTcpKernel() {
  local connFileName="$1"

  printf '\n====== STARTING WRAPPED TCP KERNEL: %s\n' "${connFileName}"
  local tcpKernelConnFilePath="${kernelRuntimeDir}/${connFileName}"

  "${jupyterCmd}" kernel \
    --kernel="${wrappedTcpKernel}" \
    --KernelManager.connection_file="${tcpKernelConnFilePath}" \
    2> >(sed 's/^/[WRAPPED_TCP_KERNEL err]: /' >&2) | sed 's/^/[WRAPPED_TCP_KERNEL out]: /' &

  while ! [[ -f "${tcpKernelConnFilePath}" ]] && ((tcpKernelConnFileTimeout--)); do
    printf '.'; sleep 1
  done
  if ! ((tcpKernelConnFileTimeout)); then
    echo 'Error: connection file of wrapped tcp kernel is not created!' >&2
    exit 1
  fi
  printf '\n====== STARTED WRAPPED TCP KERNEL: %s\n\n' "${tcpKernelConnFileName}"
}


function startSocketForwarders() {
  local ipcFilePathPrefix="$1"
  declare -p ipcFilePathPrefix
  local -i ipcPort; for ipcPort in {1..5}; do
    socat \
      "UNIX-LISTEN:${ipcFilePathPrefix}-${ipcPort},fork" \
      "TCP:127.0.0.1:${tcpKernelPorts[ipcPort]}" &
  done
}


function createConnectionFile() {
  local filePath="$1" ip="$2" signatureScheme="$3" key="$4"
  ### IPC ports:
  # 1 shell
  # 2 iopub
  # 3 stdin
  # 4 control
  # 5 hb
  sed 's/ *#.*$//' <<EOF > "${filePath}"
  {
    "transport": "ipc",
    "ip": "${ip}",
    "shell_port": 1,    # shell
    "iopub_port": 2,    # iopub
    "stdin_port": 3,    # stdin
    "control_port": 4,  # control
    "hb_port": 5,       # hb
    "signature_scheme": "${signatureScheme}",
    "key": "${key}",
    "kernel_name": ""
  }
EOF
}


function terminateSubprocesses() {
  local -a subProcPids; readarray -t subProcPids < <( jobs -p )
  printf 'Terminating %s ...' "${subProcPids[*]}"
  kill "${subProcPids[@]}"
  wait -f
  printf 'SUCCESS\n'
}



### MAIN

printf '\nconnect using e.g.:\n'
printf '%q console --existing %q\n\n' "${jupyterCmd}" "${connFile##*/}"

declare tcpKernelConnFileName; tcpKernelConnFileName="kernel-$( uuid ).json"

startWrappedTcpKernel "${tcpKernelConnFileName}"

# parse wrapped kernel connection file
{
  declare -a tcpKernelPorts; readarray -t -O 1 -n 5 tcpKernelPorts
  declare signatureScheme key; read -r signatureScheme; read -r key
  declare -p tcpKernelPorts signatureScheme key
} < <(
  jq -r '.[$ARGS.positional[]]' \
    --args 'shell_port' 'iopub_port' 'stdin_port' 'control_port' 'hb_port' 'signature_scheme' 'key' \
    < "${kernelRuntimeDir}/${tcpKernelConnFileName}"
)

declare ipcFilePathPrefix="${connFile%".json"}-ipc"
declare -p ipcFilePathPrefix

trap 'terminateSubprocesses' EXIT

startSocketForwarders "${connFile%".json"}-ipc"

createConnectionFile "${connFile}" "${ipcFilePathPrefix}" "${signatureScheme}" "${key}"

wait -f
