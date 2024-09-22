#!/usr/bin/env bash
set -e
set -o pipefail
logFile=${HOME}/master_$(date +%Y%m%d%H%M).log
source /vagrant/scripts/lib.sh


function runSingleMaster() {
  logCurrentFunction "start"
  kubeadmInitSinaleMaster
  exportKubeConfig
  installFlannel
  exportJoinWorkerScript "$1"
  logCurrentFunction "end"
}

runSingleMaster "$logFile" 2>&1 | tee -a "${logFile}"