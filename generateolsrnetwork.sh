#!/bin/bash

#
#  Copyright 2017 Claudio Pisa (clauz at ninux dot org)
#
#  This file is part of meshinarouter
#
#  meshinarouter is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  meshinarouter is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with meshinarouter.  If not, see <http://www.gnu.org/licenses/>.
#


set -e
set -x

NNODES=${1:-5}
LPROB=${2:-2500} # /10000

addinitiallink() {
    # add the first veth from the first netns to a newly created ns
    ip netns add olsr${1}
    ip netns exec olsr${1} ip addr add 127.0.0.1 dev lo
    ip netns exec olsr${1} ip link set lo up
    ip link add o${1}o0 type veth peer name o${1}o1
    ip link set o${1}o1 netns olsr${1}
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
        echo -n " \"$i\""               >> $CFGFILENAME
    done
    echo ""                             >> $CFGFILENAME
    echo "{"                            >> $CFGFILENAME
    echo " HelloInterval       2.0"     >> $CFGFILENAME
    echo " HelloValidityTime   20.0"    >> $CFGFILENAME
    echo " TcInterval          5.0"     >> $CFGFILENAME
    echo " TcValidityTime      300.0"   >> $CFGFILENAME
    echo " MidInterval         5.0"     >> $CFGFILENAME
    echo " MidValidityTime     300.0"   >> $CFGFILENAME
    echo " HnaInterval         5.0"     >> $CFGFILENAME
    echo " HnaValidityTime     300.0"   >> $CFGFILENAME
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

createantenna () {
    i=${1} # antenna number
    j=${2} # olsr node to connect to
    vlanid=${3}

    antennans=antenna${i}
    ip netns add $antennans
    ip link set o${j}o0 netns $antennans
    ip link add a${i}v0 type veth peer name a${i}v1
    ip link set a${i}v1 netns $antennans
    ip netns exec $antennans ip link add link a${i}v1 vlan${vlanid} type vlan id $vlanid
    ip netns exec $antennans brctl addbr br0
    ip netns exec $antennans brctl addif br0 o${j}o0
    ip netns exec $antennans brctl addif br0 vlan${vlanid}
    ip netns exec $antennans ip link set o${j}o0 up
    ip netns exec $antennans ip link set a${i}v1 up
    ip netns exec $antennans ip link set vlan${vlanid} up
    ip netns exec $antennans ip link set br0 up
    ip link set a${i}v0 up
    brctl addif br0 a${i}v0
}

# initialize br0
brctl addbr br0 || true
brctl addif br0 eth0 || true
ip link set br0 up

# create the links
for i in $(seq 1 $NNODES); do
    OIF=$(addinitiallink ${i})
    for j in $(seq 1 $i); do
        # link to node j according to probability
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

# emulate the antennae
createantenna 1 1 10
createantenna 2 $NNODES 20


