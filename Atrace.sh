#!/usr/bin/env bash
#echo $BASH_VERSION
# Filename: Atrace.sh
# Author: Ethan Nelson
# Date created: 12 October 2020
# Last modified: 11 December 2020

#-------------------------------------------------------------------------------
# Global Variables
#-------------------------------------------------------------------------------
#Sites to test response times
#sites: Cam.co.uk
        #Politico.eu
        #Yahoo.co.jp
        #unimelb.edu.au
        #uni.edu
        #ucla.edu
        #apple.com
        #Amazon.com
        #IBM.com
        #Yahoo.com
SITE_LIST=(128.232.132.8
           104.26.9.117
           182.22.59.229
           43.245.43.59
           134.161.7.207
           128.97.27.37
           17.253.144.10
           205.251.242.103
           129.42.38.10
           74.6.143.26)

#Packet sizes to test against each website
PACKET_SIZES=(100 300 600 900 1200)

#Name of the database to store all of the test results
DB_NAME="ProjectDB.db"

#function variables that need to be passed to eachother
#resets each array after use
MK_ARRAY_TMP=()
T_HLINE_NUM=()
T_HLINE_SERV=()
T_HLINE_RTT=()
T_THOPNUM=""

#Stores date and time (obviously)
DATE=""
TIME=""

#-------------------------------------------------------------------------------
# Database Functions
#-------------------------------------------------------------------------------
#Creates the database
#Contains two tables Site & mksRoute (stands for 'makes route')
#Site lists each website with the varying indepedent variables: time, packetSize
#mksRoute lists the route component of each website.
#   Disclaimer: each entry is only a portion of the total route.
#               In order to obtain the entire route, a little SQL selection magic
#               needs to be done
startDB ()
{
  if [ ! -f "$DB_NAME" ]
    then
      tables="CREATE TABLE Site(
                            date DATE,
                            time TIME,
                            siteName VARCHAR(20),
                            packetSize INT(4),
                            hops INT(2),
                            RTT DECIMAL(7,3));
              CREATE TABLE mksRoute(
                            date DATE,
                            time TIME,
                            siteName VARCHAR(20),
                            packetSize INT(4),
                            hopNum INT(2),
                            hopServer VARCHAR(20),
                            hopRTT DECIMAL(7,3));"
      sqlite3 "$DB_NAME" "$tables"
  fi
  return 0
}

#Formats the inputs into a SQLite friendly syntax &
#updates the database depedent on the table type
#   Disclaimer: I am aware that this bit of code is vulnerable to SQL injection, however
#               since this is for a research project and not for commercial use,
#               I am not going to fix it.
updateDB ()
{
  #table type: $1
  #entry data: $@ (after shift)
  filter=$1
  shift
  data=("$@")
  runCommand=""

  case "$filter" in
    site)runCommand="INSERT INTO Site VALUES('${data[0]}','${data[1]}','${data[2]}',${data[3]},${data[4]},${data[5]});";;
    mksRoute)runCommand="INSERT INTO mksRoute VALUES('${data[0]}','${data[1]}','${data[2]}',${data[3]},${data[4]},'${data[5]}',${data[6]});";;
    *) return 0
  esac
  sqlite3 "$DB_NAME" "$runCommand"
  return 0
}

#-------------------------------------------------------------------------------
# Parsing Functions
#-------------------------------------------------------------------------------
#Parses Traceroute and stores the data into temporary arrays
parseTrace ()
{
  #array of: hopLine: (hopNum, hopServer, hopRTT)
  #Traceroute Output: $1
  mkArray "$1"
  MK_ARRAY_TMP=("${MK_ARRAY_TMP[@]:1}")

  T_THOPNUM=$(echo "${MK_ARRAY_TMP[-1]}" | awk -F"  " '{print$1}' | sed 's/ *//g')

  for block in "${MK_ARRAY_TMP[@]}"
  do
    hopNum=$(echo "$block" | awk -F"  " '{print$1}' | sed 's/ *//g')
    hopServer=$(echo "$block" | awk -F"  " '{print$2}')
    hopRTT=$(echo "$block" | awk -F"  " '{print$3}' | awk -F" " '{print$1}')

    if [[ $hopRTT == "" || hopRTT == "\*" ]]; then hopRTT="-1"; fi

    T_HLINE_NUM+=("$hopNum")
    T_HLINE_SERV+=("$hopServer")
    T_HLINE_RTT+=("$hopRTT")
  done
}

#Parses the ping output and returns the average RTT
parsePing ()
{
  #pingOutput: $1
  line=$(echo $1 | tail -n1)
  avgRTT=$(echo $line | awk -F"/" '{print$5}')
  echo "$avgRTT"
}
#-------------------------------------------------------------------------------
# Misc. Helper Functions
#-------------------------------------------------------------------------------
# a time storing helper function
time_func ()
{

  DATE=$(date +%Y-%m-%d)
  TIME=$(date +%H:%M:%S)
  return 0
}

#a little array maker helper function
mkArray ()
{
  while IFS= read -r line; do
    MK_ARRAY_TMP+=("$line")
  done <<< "$1"
}
#-------------------------------------------------------------------------------
# Main Function
#-------------------------------------------------------------------------------

#Starts the Ping and Traceroute programs to gather data
#Iterates through the each site and each packet size to test
#Resets the temporary arrays after each iteration
Connect ()
{
  for site in ${SITE_LIST[@]}
  do
    for size in ${PACKET_SIZES[@]}
    do
      trace=$(traceroute -n -q1 -I -w1 -m60 $site $size)

      pingSize=$(( $size - 8 ))
      pingDat=$(ping -c3 -q -s$pingSize $site)

      parseTrace "$trace"
      avgRTT=$(parsePing "$pingDat")

      siteDB=("$DATE" "$TIME" "$site" "$size" "$T_THOPNUM" "$avgRTT")

      for ((i=0; i < $T_THOPNUM; i++))
      do
        route=("$DATE" "$TIME" "$site" "$size" "${T_HLINE_NUM[$i]}" "${T_HLINE_SERV[$i]}" "${T_HLINE_RTT[$i]}")
        updateDB mksRoute "${route[@]}"
      done

      updateDB site "${siteDB[@]}"
      MK_ARRAY_TMP=()
      T_HLINE_NUM=()
      T_HLINE_SERV=()
      T_HLINE_RTT=()
    done
  done

}

#Executes the necessary required functions before the main function
time_func
startDB
Connect
