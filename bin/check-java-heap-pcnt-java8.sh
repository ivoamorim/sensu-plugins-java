#!/usr/bin/env bash
#
# Evaluate percentage of heap usage on specfic Tomcat backed JVM from Linux based systems based on percentage
# This was forked from Sensu Community Plugins

# Date: 2017-02-10
# Modified: Nikoletta Kyriakidou

# Date: 2018-08-30
# Modified: Juan Moreno Martinez - Change MAX HEAP instead Current HEAP

# You must have openjdk-8-jdk and openjdk-8-jre packages installed
# http://openjdk.java.net/install/
#
# Also make sure the user "sensu" can sudo without password

# #RED
while getopts 'w:c:n:o:j:l:a:hp' OPT; do
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
JAVA_BIN=${JAVA_BIN:=""}
ALL=${ALL_NAMES:=0}



function check_java_heap()
{
NAME=$1
#Get PIDs of JVM.
#At this point grep for the names of the java processes running your jvm.
PIDS=$(sudo ${JAVA_BIN}jps $OPTIONS | grep " $NAME$" | awk '{ print $1}')

projectSize=$(printf "%s\n" $(printf "$PIDS" | wc -w))

i=0
for PID in $PIDS
do
  #Get heap capacity of JVM
  if [ "$HEAP_MAX" == "" ] || [ "$HEAP_MAX" == "current" ]; then
    TotalHeap=$(sudo ${JAVA_BIN}jstat -gccapacity $PID  | tail -n 1 | awk '{ print ($4 + $5 + $6 + $10) / 1024 }')
  elif [[ "$HEAP_MAX" == "max" ]]; then
    TotalHeap=$(sudo ${JAVA_BIN}jmap -heap $PID 2> /dev/null | grep MaxHeapSize | tr -s " " | tail -n1 | awk '{ print $3 /1024 /1024 }')
  else
    echo "limit options must be max or current"
    exit 1
  fi

	#Determine amount of used heap JVM is using
	UsedHeap=$(sudo ${JAVA_BIN}jstat -gc $PID  | tail -n 1 | awk '{ print ($3 + $4 + $6 + $8) / 1024 }')

	#Get heap usage percentage
	HeapPer=$(echo "scale=3; $UsedHeap / $TotalHeap * 100" | bc -l| cut -d "." -f1)


	if [ "$HeapPer" = "" ]; then
	  echo "MEM UNKNOWN -"
	  codes[i]=3
	fi

	#For multiple projects running we need to print the name
	if [ "$projectSize" -ne 1 ]; then
		projectName=$(sudo jps | grep $PID | awk '{ print $2}' | cut -d. -f1)
		project=$projectName
	fi

	if [ "$perform" = "yes" ]; then
	  output="$project jvm heap usage: $HeapPer% | heap usage="$HeapPer"%;$WARN;$CRIT;0"
	else
	  output="$project jvm heap usage: $HeapPer% | $UsedHeap MB out of $TotalHeap MB"
	fi

	if (( $HeapPer >= $CRIT )); then
	  echo "MEM CRITICAL - $output"
 	  codes[i]=2
	elif (( $HeapPer >= $WARN )); then
	  echo "MEM WARNING - $output"
	  codes[i]=1
	else
	  echo "MEM OK - $output"
	  codes[i]=0
	fi
	i+=1
done

if (($projectSize -ne $1 && ${codes[0]} != "0")); then
	exit ${codes[1]}
else
	exit ${codes[0]}
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