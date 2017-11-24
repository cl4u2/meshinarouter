#!/bin/bash

set -x

NNODES=${1:-5}

killall olsrd

for i in $(seq 0 $NNODES); do
    ip netns del olsr${i}
done

ip link show | grep ': o' | awk '{print $2}' | awk -F'@' '{print $1}' | while read line; do
    ip link del $line
done



