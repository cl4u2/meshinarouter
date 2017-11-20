#!/bin/bash

set -x

NNODES=${1:-5}

killall olsrd

for i in $(seq 1 $NNODES); do
    ip link del br${i}
done

ip link show | grep ': o' | awk '{print $2}' | awk -F'@' '{print $1}' | while read line; do
    ip link del $line
done



