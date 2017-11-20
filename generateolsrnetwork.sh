#!/bin/bash

set -e
set -x

NNODES=${1:-5}
LPROB=${2:-0} # /10000
FIRSTBRIDGE=${3:-br0}

addinitiallink() {
    brctl addbr br${1}
    ip link set br${1} up
    brctl setageing br${1} 0
    echo br${1}
}

addlink() {
    ip link add o${1}o0 type veth peer name o${1}o1
    ip link set o${1}o0 up
    ip link set o${1}o1 up
    brctl addif br${2} o${1}o0
    brctl addif br${3} o${1}o1
}

createconfigfile() {
    CFGFILENAME=/tmp/olsrd${1}.conf
    cp olsrdo0.conf $CFGFILENAME
    echo "LockFile \"/tmp/o${1}.lock\"" >> $CFGFILENAME
    echo "RtTable $1" >> $CFGFILENAME
    echo $CFGFILENAME
}

doprob() {
    n=$((RANDOM % 10000))
    [ $n -lt $LPROB ]
}

for i in $(seq 1 $NNODES); do
    OIF=$(addinitiallink ${i})
    ip addr add fdcc:cccc:cccc::${i}/128 dev $OIF
    # link to $FIRSTBRIDGE
    addlink ${i}0 ${i} 0
    for j in $(seq 1 $i); do
        # if probability link to node j
        if [ $i != $j ]; then
            if doprob; then
                addlink ${i}${j} ${i} ${j}
            fi
        fi
    done
    CFG=$(createconfigfile $i)
    olsrd -f $CFG -d 0 -i $OIF -ipv6 -multi ff02::2 
done


