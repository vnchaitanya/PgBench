#!/bin/bash
set +H

Settingfile=$1

export Duration=`jq -r '.TestConfig.Duration' $Settingfile`
capture_duration=$((Duration -30))
filetag=Logs/LogFile_`hostname`

capture_cpu_SystemFile=/tmp/capture_cpu_System_Top.log
capture_cpu_PgBenchFile=/tmp/capture_cpu_PgBench_Top.log
capture_connectionsFile=/tmp/capture_connections.log
capture_memory_usageFile=/tmp/capture_memory_usage.log
capture_netusageFile=/tmp/capture_netusage_sar.log

capture_server_connectionsFile=/tmp/capture_server_connections.log
capture_server_netusageFile=/tmp/capture_server_netusage_sar.log
capture_server_diskusageFile=/tmp/capture_server_diskusage.log
capture_server_cpu_SystemFile=/tmp/capture_server_cpu_System_Top.log
capture_server_memory_usageFile=/tmp/capture_server_memory_usage.log

export COLLECT_SERVER_STATS=1

capture_cpu(){
    sleep 10
    for i in $(seq 1 $capture_duration)
    do
        top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' >> $capture_cpu_SystemFile
        top -bn1 | awk '/pgbench/ {print $9,$10}' >> $capture_cpu_PgBenchFile
        sleep 1
    done
}

capture_connections(){
    sleep 10
	for i in $(seq 1 $capture_duration)
	do
		#netstat -natp | grep pgbench | grep ESTA | wc -l >> $filetag-connections_$Iteration.csv
		netstat -taepn 2>/dev/null | grep pgbench | grep ESTA | wc -l >> $capture_connectionsFile
		sleep 1
	done
}

capture_memory_usage(){
    sleep 10
    #$ free -m
    #              total        used        free      shared  buff/cache   available
    #Mem:          28136        1191       25672          68        1272       26332
    #Swap:             0           0           0
	for i in $(seq 1 $capture_duration)
	do
        free -m|awk '/Mem/{print $2, $3, $4}' >> $capture_memory_usageFile
		sleep 1
	done
    #vmstat 1 $capture_duration >> $filetag-vmstat_$Iteration.csv
}

capture_netusage(){
    sleep 10
    sar -n DEV 1 $capture_duration 2>&1 >> $capture_netusageFile
}

get_captured_server_usages(){
    echo "Server VM stats (Average) during test :-------------------------"
    if [ -f $capture_server_netusageFile ]
    then
        echo "ServerNetwork "`cat $capture_server_netusageFile| grep Average| head -1|awk '{print $5}'` ":" `cat $capture_server_netusageFile| grep Average|grep eth0| awk '{print $5}'`
        echo "ServerNetwork "`cat $capture_server_netusageFile| grep Average| head -1|awk '{print $6}'` ":" `cat $capture_server_netusageFile| grep Average|grep eth0| awk '{print $6}'`
    fi
    echo "ServerConnections : " `get_Column_Avg $capture_server_connectionsFile`
    echo "ServerCPU usage (OS): " `get_Column_Avg $capture_server_cpu_SystemFile`
    echo "ServerMemory stats OS (total,used,free): " `get_Column_Avg $capture_server_memory_usageFile`

    echo "ServerDiskUsage: IOPS,MbpsRead,MbpsWrite :-----" 
    disk_list=(`cat $capture_server_diskusageFile | grep ^sd| awk '{print $1}' |sort |uniq`)

    count=0
    while [ "x${disk_list[$count]}" != "x" ]
    do
        disk=${disk_list[$count]}
        
        cat $capture_server_diskusageFile | grep ^$disk| awk '{print $2"\t"$3"\t"$4}' > $capture_server_diskusageFile.tmp
        echo "ServerDisk "$disk ": "`get_Column_Avg $capture_server_diskusageFile.tmp`
        ((count++))
    done   

    echo "ServerDiskUsageIOPS: Min,Max :-----" 

    count=0
    while [ "x${disk_list[$count]}" != "x" ]
    do
        disk=${disk_list[$count]}
        
        IOPS_Array=(`cat $capture_server_diskusageFile | grep ^$disk| awk '{print $2}'`)
        echo "ServerDiskIOPSMinMax "$disk ": "`get_MinMax ${IOPS_Array[@]}`
        ((count++))
    done   

    echo "ServerDiskUsage Read MBps: Min,Max :-----" 

    count=0
    while [ "x${disk_list[$count]}" != "x" ]
    do
        disk=${disk_list[$count]}
        
        IOPS_Array=(`cat $capture_server_diskusageFile | grep ^$disk| awk '{print $3}'`)
        echo "ServerDiskReadMBpsMinMax "$disk ": "`get_MinMax ${IOPS_Array[@]}`
        ((count++))
    done   

    echo "ServerDiskUsage Write MBps: Min,Max :-----" 

    count=0
    while [ "x${disk_list[$count]}" != "x" ]
    do
        disk=${disk_list[$count]}
        
        IOPS_Array=(`cat $capture_server_diskusageFile | grep ^$disk| awk '{print $4}'`)
        echo "ServerDiskWriteMBpsMinMax "$disk ": "`get_MinMax ${IOPS_Array[@]}`
        ((count++))
    done   
}

get_MinMax(){

    inputArray=("$@")
    count=${#inputArray[@]}
    lastIndex=$((count-1))

    IFS=$'\n' sorted=($(sort -n <<<"${inputArray[*]}"))
    unset IFS
    min=`printf "%.f\n" ${sorted[0]}`
    max=`printf "%.f\n" ${sorted[$lastIndex]}`
    echo "$min,$max"
}

get_Avg(){

    inputArray=("$@")
    count=${#inputArray[@]}
    sum=$( IFS="+"; bc <<< "${inputArray[*]}" )
    unset IFS
    average=`echo $sum/$count|bc -l`
    printf "%.3f\n" $average
}

get_Column_Avg(){

    local filename=$1
    local results
    columns=`tail -1 $filename |wc -w`
    i=0
    for j in $(seq 1 $columns)
    do
        results[$i]=`get_Avg $(cat $filename | awk -vcol=$j '{print $col}')`
        ((i++))
    done
    echo ${results[*]}| sed 's/ /,/g'
}
###TODO 
check_pgserver(){

    pg_isready  -U $UserName postgres://$Server:$ServerPort/postgres
#pg_isready command and check up status
#use psql check user and pass working
}
check_ssh(){

    ServerSshUsername=`jq -r '.TestConfig.ServerSshUsername' $Settingfile`
    ServerSshUsername=`jq -r '.TestConfig.ServerSshPassword' $Settingfile`
#ssh username@ip "hostname"
#P03
}
RunSshCommand(){
    #
}
start_Capture(){
    $capture_cpu_PgBenchFile
    echo > $capture_cpu_PgBenchFile
    echo > $capture_connectionsFile
    echo > $capture_memory_usageFile
    echo > $capture_netusageFile

    procs=( "capture_netusage" "capture_memory_usage" "capture_cpu" "capture_connections" )

    # Start processes and store pids in array
    i=0
    for cmd in ${procs[*]}
    do
        $cmd &
        pids[${i}]=$!
        ((i++))
    done
    
    if [ $COLLECT_SERVER_STATS == 1 ]
    then
        echo "Starting stat collection on server"
        ssh $Server "bash ~/W/RunCollectServerStats.sh"
    fi
}
###TODO End
pgBenchTest (){

    Server=`jq -r '.ServerConfig.Server' $Settingfile`
    UserName=`jq -r '.ServerConfig.UserName' $Settingfile`
    PassWord=`jq -r '.ServerConfig.PassWord' $Settingfile`
    ServerPort=`jq -r '.ServerConfig.ServerPort' $Settingfile`
    ScaleFactor=`jq -r '.ServerConfig.ScaleFactor' $Settingfile`
    Connections=`jq -r '.TestConfig.Connections' $Settingfile`
    Threads=`jq -r '.TestConfig.Threads' $Settingfile`
    TestMode=`jq -r '.TestConfig.TestMode' $Settingfile`
    
    UseExistingPgBenchDB=False
    NewConnForEachTx=False

    echo "Executing test in $TestMode mode"

    if [ "x$Server" == "x"  ]
    then
        echo "Exiting the test as no config found for this server!"
        exit 1
    else
        echo "TestMode: $TestMode"
    fi

   
    echo "-------- Client Machine Details -------- `date`"
    echo "VMcores: "`nproc`
    echo "TotalMemory: "`free -h|grep Mem|awk '{print $2}'`
    echo "KernelVersion: "`uname -r`
    echo "OSVersion: "`lsb_release -a 2>/dev/null |grep Description| sed 's/Description://'|sed 's/\s//'|sed 's/\s/_/g'`
    echo "HostVersion: "`dmesg | grep "Host Build" | sed "s/.*Host Build://"| awk '{print  $1}'| sed "s/;//"`
    echo "-------- Test parameters -------- `date`"
    echo "Server: "$Server
    echo "ScaleFactor: "$ScaleFactor
    echo "Clients: "$Connections
    echo "Threads: "$Threads
    
    echo "Starting the test.."
    Iteration=1
    while sleep  1
    do
        if [ $UseExistingPgBenchDB =="True" || $Iteration == 1 ]
        then #UseExistingPgBenchDB Add
            echo "-------- Initializing db... -------- `date`"

            echo "PGPASSWORD=$PassWord pgbench -i -s $ScaleFactor -U $UserName postgres://$Server:$ServerPort/postgres"
            startTime=`date +%s`
            PGPASSWORD=$PassWord pgbench -i -s $ScaleFactor -U $UserName postgres://$Server:$ServerPort/postgres  2>&1
            endTime=`date +%s`

            echo ""
            echo "-------- Initializing db... Done in $((endTime-startTime)) seconds -------- "
        fi
        echo "-------- Starting the test iteration: $Iteration -------- `date`"
        echo "Sleeping for 15 secs.."
        sleep 15
        echo "Sleeping for 15 secs..Done!"
    ####  (Start capture) Moved it outside the function  
    ####
        if [ "x$NewConnForEachTx" != "xFalse" ] 
        then
            PgBenchOptions="-C"
        fi
            ### Make command as a var  print and exec
        echo "Executing: PGPASSWORD=$PassWord pgbench -P 30 -c $Connections -j $Threads -T $Duration -U $UserName postgres://$Server:$ServerPort/postgres"

        PGPASSWORD=$PassWord pgbench -P 60 $PgBenchOptions -c $Connections -j $Threads -T $Duration -U $UserName postgres://$Server:$ServerPort/postgres 2>&1
####       ####
        echo "Waiting for all procs to exit" #change this
        for pid in ${pids[*]}
        do
            kill -9 $pid 2>/dev/null 
        done

        mkdir -p Logs/$Connections/$Iteration 

        if [ $COLLECT_SERVER_STATS == 1 ]
        then
            scp $Server:/tmp/capture_server* /tmp/
            scp $Server:/tmp/capture_server* Logs/$Connections/$Iteration/
        fi

        echo "Client VM stats (Average) during test:--------------------"
        echo "Network "`cat $capture_netusageFile|awk '/Average/&&/s/ {print $5}'` ":" `cat $capture_netusageFile| awk '/Average/&&/eth0/{print $5}'`
        echo "Network "`cat $capture_netusageFile|awk '/Average/&&/s/ {print $5}'` ":" `cat $capture_netusageFile| awk '/Average/&&/eth0/{print $6}'`
        echo "Memory stats OS (total,used,free): " `get_Column_Avg $capture_memory_usageFile`
        echo "Connections : " `get_Column_Avg $capture_connectionsFile`
        echo "CPU usage (OS): " `get_Column_Avg $capture_cpu_SystemFile`
        echo "CPU,MEM usage (pgbench): " `get_Column_Avg $capture_cpu_PgBenchFile`

        if [ $COLLECT_SERVER_STATS == 1 ]
        then
            get_captured_server_usages
        fi

        dmesg > Logs/$Connections/$Iteration/$filetag-dmesg.log 
####
        echo "-------- End of the test iteration: $Iteration -------- "

        if [ $TestMode == $PerformanceTestMode ]; then
        # 1 iteration is enough for PerformanceTest
            break
        fi
        Iteration=$((Iteration + 1))
    done

}

CheckDependencies(){

    if [ ! -f pgbench_config.json ]; then
        echo "ERROR: pgbench_config.json: File not found!"
        exit 1
    fi

    if [[ `which sar` == "" ]]; then
        echo "INFO: sysstat: not installed!"
        echo "INFO: sysstat: Trying to install!"
        sudo apt install sysstat -y
    fi
###Check jq installed or not
    if [[ `which jq` == "" ]]; then
        echo "INFO: jq: not installed!"
        echo "INFO: jq: Trying to install!"
        sudo apt install jq -y
    fi

    if [[ `which pgbench` == "" ]]; then
        echo "INFO: pgbench: not installed!"
        echo "INFO: pgbench: Trying to install!"
        sudo apt install postgresql-contrib -y
    fi
}

###############################################################
##
##              Script Execution Starts from here
###############################################################

CheckDependencies

pkill pgbench

if [ -d Logs ]; then
    folder=OldLogs/`date|sed "s/ /_/g"| sed "s/:/_/g"`
    mkdir -p $folder
    mv Logs/* $folder/
fi

LogFile=$filetag.log

[ ! -d Logs  ] && mkdir Logs

pgBenchTest > $LogFile 2>&1
