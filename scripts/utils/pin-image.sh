#!/bin/bash
# $1: image name, e.g. docker.io/prom/prometheus:v2.53.1
sudo ctr -n k8s.io images label "$1"  io.cri-containerd.pinned=pinned