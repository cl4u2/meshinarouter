#!/bin/bash

set -e
set -x

NNODES=${1:-5}
LPROB=${2:-0} # /10000
FIRSTBRIDGE=${3:-br0}

addinitiallink() {
    brctl addbr br${1}
    ip link set br${1} up
    ip link add o${1}o0 type veth peer name o${1}o1
    ip link set o${1}o0 up
    ip link set o${1}o1 up
    brctl addif br${1} o${1}o1
    echo o${1}o0
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
    echo $CFGFILENAME
}

doprob() {
    n=$((RANDOM % 10000))
    [ $n -lt $LPROB ]
}

for i in $(seq 1 $NNODES); do
    OIF=$(addinitiallink ${i})
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
    ip addr add 172.31.0.${i}/32 broadcast 172.31.0.255 dev $OIF
    olsrd -f $CFG -d 0 -i $OIF 
done


