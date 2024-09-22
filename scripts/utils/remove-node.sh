#!/bin/bash
set -e
set -o pipefail
kubectl drain "$1" --delete-emptydir-data --force --ignore-daemonsets
kubectl delete node "$1"