#!/usr/bin/env bash
set -e
set -o pipefail
source /vagrant/scripts/lib.sh
logFile=${HOME}/common_$(date +%Y%m%d%H%M).log

function runCommon() {
  logCurrentFunction "start"
  setTimeZone
  enableTimeSync
  createAlias
  setRootPassword
  closeSwap
  configSysctl
  enablePromisc
  configAptMirror
  configAptMirrorDockerCE
  configAptMirrorK8s
  aptUpdate
  installAllPackages
  configContainerd
  configNodeIp 
  configCrictl
  logCurrentFunction "end"
}

runCommon 2>&1 | tee -a "${logFile}"