#!/usr/bin/env bash
set -e
set -o pipefail
logFile=${HOME}/master_$(date +%Y%m%d%H%M).log
source /vagrant/scripts/lib.sh

master_seq=${1:-1}
master_count=${2:-3}
echo "master_seq: $master_seq, master_count: $master_count"

function runFirstMaster() {
  logCurrentFunction "start"
  installNginx
  installKeepalived $master_seq $master_count
  kubeadmInitFirstMaster 
  exportKubeConfig
  installFlannel
  exportJoinWorkerScript "$1"
  exportJoinMasterScript "$1"
  logCurrentFunction "end"
}

function runRemainMaster() {
  logCurrentFunction "start"
  installNginx
  installKeepalived $master_seq $master_count
  joinMaster
  configKubectl
  logCurrentFunction "end"
}

if [ "$1" == "1" ]; then
  runFirstMaster "$logFile" 2>&1 | tee -a "${logFile}"
else
  runRemainMaster "$logFile" 2>&1 | tee -a "${logFile}"
fi