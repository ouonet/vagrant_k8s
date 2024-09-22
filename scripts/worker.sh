#!/bin/bash
set -e
set -o pipefail
logFile=${HOME}/worker_$(date +%Y%m%d%H%M).log
source /vagrant/scripts/lib.sh

function runWorker() {
  logCurrentFunction "start"

  joinWorker
  configKubectl
  configKubeletImageGC

  logCurrentFunction "end"
}

runWorker 2>&1 | tee -a "${logFile}"