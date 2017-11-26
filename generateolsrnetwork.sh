#!/bin/bash

set -e
set -x

NNODES=${1:-5}
LPROB=${2:-0} # /10000

addinitiallink() {
    # add the first veth from the main netns to a newly created ns
    ip netns add olsr${1}
	ip netns exec olsr${1} ip addr add 127.0.0.1 dev lo
	ip netns exec olsr${1} ip link set lo up
    ip link add o${1}o0 type veth peer name o${1}o1
    ip link set o${1}o0 netns olsr0
    ip link set o${1}o1 netns olsr${1}
    ip netns exec olsr0    ip addr add 172.31.0.${1}/32   brd 172.31.255.255 dev o${1}o0
    ip netns exec olsr0    ip link set o${1}o0 up
    ip netns exec olsr${1} ip addr add 172.31.${1}.100/32 brd 172.31.255.255 dev o${1}o1
    ip netns exec olsr${1} ip link set o${1}o1 up
    echo o${1}o1
}

addlink() {
    # add a veth between two namespaces
    ip link add o${1}${2}o0 type veth peer name o${1}${2}o1
    ip link set o${1}${2}o0 netns olsr${1}
    ip link set o${1}${2}o1 netns olsr${2}
    ip netns exec olsr${1} ip addr add 172.31.${1}.${2}/32 brd 172.31.255.255 dev o${1}${2}o0
    ip netns exec olsr${2} ip addr add 172.31.${2}.${1}/32 brd 172.31.255.255 dev o${1}${2}o1
    ip netns exec olsr${1} ip link set o${1}${2}o0 up
    ip netns exec olsr${2} ip link set o${1}${2}o1 up
    echo o${1}${2}o0
}

createconfigfile() {
    # generate an olsrd configuration file
    N=$1
    shift
    CFGFILENAME=/tmp/olsrd${N}.conf
    cp olsrdo0.conf $CFGFILENAME
    echo -n "Interface"                 >> $CFGFILENAME
    for i in $@; do
        echo -n " \"$i\""                  >> $CFGFILENAME
    done
    echo ""                             >> $CFGFILENAME
    echo "{"                            >> $CFGFILENAME
    echo " HelloInterval       2.0"     >> $CFGFILENAME
    echo " HelloValidityTime   20.0"     >> $CFGFILENAME
    echo " TcInterval          5.0"     >> $CFGFILENAME
    echo " TcValidityTime      300.0"     >> $CFGFILENAME
    echo " MidInterval         5.0"     >> $CFGFILENAME
    echo " MidValidityTime     300.0"     >> $CFGFILENAME
    echo " HnaInterval         5.0"     >> $CFGFILENAME
    echo " HnaValidityTime     300.0"     >> $CFGFILENAME
    echo "}"                            >> $CFGFILENAME
    echo ""                             >> $CFGFILENAME
    echo "LockFile \"/tmp/o${N}.lock\"" >> $CFGFILENAME
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


ip netns add olsr0
ip netns exec olsr0 ip addr add 127.0.0.1 dev lo
ip netns exec olsr0 ip link set lo up
ip link add veth0 type veth peer name veth1
ip link set veth1 netns olsr0
ip netns exec olsr0 ip addr add 172.31.0.200/32 brd 255.255.255.255 dev veth1
ip netns exec olsr0 ip link set veth1 up
ip link set veth0 up
brctl addif br-lan veth0

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
    IFACES=$(listinterfaces $i)
    CFG=$(createconfigfile $i $IFACES)
    ip netns exec olsr${i} olsrd -f $CFG -d 0 
done

# start olsrd in the current namespace
IFACES=""
for i in $(seq 1 $NNODES); do
    IFACES="o${i}o0 $IFACES"
done
CFG=$(createconfigfile 0 "$IFACES veth1")
ip netns exec olsr0 olsrd -f $CFG -d 1 

