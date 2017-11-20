#!/bin/bash

set -e
set -x

NNODES=${1:-5}
LPROB=${2:-0} # /10000
FIRSTBRIDGE=${3:-br0}

addinitiallink() {
    # add the first veth from the main netns to a newly created ns
    ip netns add olsr${1}
    ip link add o${1}o0 type veth peer name o${1}o1
    ip link set o${1}o1 netns olsr${1}
    ip netns exec olsr${1} ip addr add 172.31.${1}.0/16 broadcast 172.31.255.255 dev o${1}o1
    ip netns exec olsr${1} ip link set o${1}o1 up
    ip addr add 172.31.0.${1}/16 broadcast 172.31.255.255 dev o${1}o0
    ip link set o${1}o0 up
    brctl addif $FIRSTBRIDGE o${1}o0
    echo o${1}o1
}

addlink() {
    # add a veth between two namespaces
    ip link add o${1}${2}o0 type veth peer name o${1}${2}o1
    ip link set o${1}${2}o0 netns olsr${1}
    ip link set o${1}${2}o1 netns olsr${2}
    ip netns exec olsr${1} ip addr add 172.31.${1}.${2}/16 broadcast 172.31.255.255 dev o${1}${2}o0
    ip netns exec olsr${2} ip addr add 172.31.${2}.${1}/16 broadcast 172.31.255.255 dev o${1}${2}o1
    ip netns exec olsr${1} ip link set o${1}${2}o0 up
    ip netns exec olsr${2} ip link set o${1}${2}o1 up
    echo o${1}${2}o0
}

createconfigfile() {
    # generate an olsrd configuration file
    CFGFILENAME=/tmp/olsrd${1}.conf
    cp olsrdo0.conf $CFGFILENAME
    echo "LockFile \"/tmp/o${1}.lock\"" >> $CFGFILENAME
    echo $CFGFILENAME
}

listinterfaces() {
    # list the useful interfaces in the supplied namespace
    ip netns exec olsr${1} ip -4 a | grep ': ' | awk '{print $2}' | grep -v 'lo:' | sed 's/://g' | awk -F'@' '{print $1}' | xargs echo
}

doprob() {
    n=$((RANDOM % 10000))
    [ $n -lt $LPROB ]
}

for i in $(seq 1 $NNODES); do
    OIF=$(addinitiallink ${i})
    for j in $(seq 1 $i); do
        # if probability link to node j
        if [ $i != $j ]; then
            if doprob; then
                addlink ${i} ${j}
            fi
        fi
    done
done

# start olsrd on all namespaces
for i in $(seq 1 $NNODES); do
    CFG=$(createconfigfile $i)
    ip netns exec olsr${i} olsrd -f $CFG -d 0 -i $(listinterfaces $i)
done

# start olsrd in the current namespace
CFG=$(createconfigfile 0)
IFACES=""
for i in $(seq 1 $NNODES); do
    IFACES="o${i}o0 $IFACES"
done
olsrd -f $CFG -d 1 -i $IFACES

