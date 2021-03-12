#!/usr/bin/env bash
#
# Evaluate percentage of heap usage on specfic Tomcat backed JVM from Linux based systems based on percentage
# This was forked from Sensu Community Plugins

# Date: 2013-9-30
# Modified: Mario Harvey - badmadrad.com

# Date: 2017-06-06
# Modified: Nic Scott - re-work to be java version agnostic

# Date: 2018-08-30
# Modified: Juan Moreno Martinez - Change MAX HEAP instead Current HEAP and fix bug java agnostic

# depends on jps and jstat in openjdk-devel in openjdk-<VERSION>-jdk and
# openjdk-<VERSION>-jre packages being installed
# http://openjdk.java.net/install/

# Also make sure the user "sensu" can sudo jps and jstat without password

while getopts 'w:c:n:o:j:l:a:hp:' OPT; do
  case $OPT in
    w)  WARN=$OPTARG;;
    c)  CRIT=$OPTARG;;
    n)  NAME=$OPTARG;;
    o)  OPTIONS=$OPTARG;;
    j)  JAVA_BIN=$OPTARG;;
    l)  HEAP_MAX=$OPTARG;;
    a)  ALL_NAMES=$OPTARG;;
    h)  hlp="yes";;
    p)  perform="yes";;
    *)  unknown="yes";;
  esac
done

# usage
HELP="
usage: $0 [ -n value -w value -c value -o value -l value -p -h ]
  -a --> All of JVM process < value
  -n --> Name of JVM process < value
  -w --> Warning Percentage < value
  -c --> Critical Percentage < value
  -o --> options to pass to jps
  -j --> path to java bin dir (include trailing /)
  -p --> print out performance data
  -h --> print this help screen
  -l --> limit, valid value max or current (default current)
         current: when -Xms and -Xmx same value
         max: when -Xms and -Xmx have different values
Requirement: User that launch script must be permisions in sudoers for jps,jstat,jmap
sudoers lines suggested:
----------
sensu ALL=(ALL) NOPASSWD: /usr/bin/jps, /usr/bin/jstat, /usr/bin/jmap
Defaults:sensu !requiretty
----------
"

if [ "$hlp" = "yes" ]; then
  echo "$HELP"
  exit 0
fi

WARN=${WARN:=0}
CRIT=${CRIT:=0}
NAME=${NAME:=0}
ALL=${ALL_NAMES:=0}
JAVA_BIN=${JAVA_BIN:=""}

#Get PID of JVM.
#At this point grep for the name of the java process running your jvm.


function check_java_heap()
{
NAME=$1
PID=$(sudo ${JAVA_BIN}jps $OPTIONS | grep " $NAME$" | awk '{ print $1}')
COUNT=$(echo $PID | wc -w)
if [ $COUNT != 1 ]; then
  echo "$COUNT java process(es) found with name $NAME"
  exit 3
fi

JSTAT=$(sudo ${JAVA_BIN}jstat -gc $PID  | tail -n 1)

# Java 8 jstat -gc returns 17 columns Java 7 returns 15
if [[ $(echo $JSTAT| wc -w) -gt 15 ]]; then
  # Metaspace is not a part of heap in Java 8
  #Get heap capacity of JVM
  TotalHeap=$(echo $JSTAT | awk '{ print ($1 + $2 + $5 + $7) / 1024 }')
  #Determine amount of used heap JVM is using
  UsedHeap=$(echo $JSTAT | awk '{ print ($3 + $4 + $6 + $8) / 1024 }')
else
  # PermGen is part of heap in Java <8
  #Get heap capacity of JVM
  TotalHeap=$(echo $JSTAT | awk '{ print ($1 + $2 + $5 + $7 + $9) / 1024 }')
  #Determine amount of used heap JVM is using
  UsedHeap=$(echo $JSTAT | awk '{ print ($3 + $4 + $6 + $8 + $10) / 1024 }')
fi


if [[ "$HEAP_MAX" == "max" ]]; then
  TotalHeap=$(sudo ${JAVA_BIN}jmap -heap $PID 2> /dev/null | grep MaxHeapSize | tr -s " " | tail -n1 | awk '{ print $3 /1024 /1024 }')
elif [ "$HEAP_MAX" != "" ] && [ "$HEAP_MAX" != "current" ]; then
  echo "limit options must be max or current"
  exit 3
fi

#Get heap usage percentage
HeapPer=$(echo "scale=3; $UsedHeap / $TotalHeap * 100" | bc -l| cut -d "." -f1)


if [ "$HeapPer" = "" ]; then
  echo "MEM UNKNOWN -"
  exit 3
fi

if [ "$perform" = "yes" ]; then
  output="jvm heap usage: $HeapPer% | heap usage="$HeapPer"%;$WARN;$CRIT;0"
else
  output="jvm heap usage: $HeapPer% | $UsedHeap MB out of $TotalHeap MB"
fi

if (( $HeapPer >= $CRIT )); then
  echo "MEM CRITICAL - $output"
  exit 2
elif (( $HeapPer >= $WARN )); then
  echo "MEM WARNING - $output"
  exit 1
else
  echo "MEM OK - $output"
  exit 0
fi
}


if [ $ALL == "yes" ]; then
    java_process_names=$(sudo ${JAVA_BIN}jps $OPTIONS | grep ".jar" | awk '{ print $2}')
    for pname in ${java_process_names}
   {
        check_java_heap $pname
    }
else
    check_java_heap $NAME
fi