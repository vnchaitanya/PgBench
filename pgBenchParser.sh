#!/bin/bash
#
# This script converts pgbench IO output file into csv format.
# Author: Srikanth Myakam
# Email	: 
####
export DEBUG=0

TestDataFile=ConnectionProperties.csv

function get_Avg()
{
    inputArray=("$@")
    count=${#inputArray[@]}
    sum=$( IFS="+"; bc <<< "${inputArray[*]}" )
    unset IFS
    average=`echo $sum/$count|bc -l`
    printf "%.3f\n" $average
}

function get_Sum()
{
    inputArray=("$@")
    sum=$( IFS="+"; bc <<< "${inputArray[*]}" )
    unset IFS
    echo $sum
}

function get_MinMax()
{
    inputArray=("$@")
    count=${#inputArray[@]}
    lastIndex=$((count-1))

    IFS=$'\n' sorted=($(sort -n <<<"${inputArray[*]}"))
    unset IFS
    min=`printf "%.3f\n" ${sorted[0]}`
    max=`printf "%.3f\n" ${sorted[$lastIndex]}`
    echo "$min,$max"
}

function Parse
{
    log_file_name=$1

    if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <pgbench-output.log>" >&2
    exit 1
    fi

    if [ ! -f $log_file_name ]; then
        echo "$1: File not found!"
        exit 1
    fi

    csv_file=`echo $log_file_name | sed "s/\.log/\.csv/"`

    res_Iteration=(`grep "Starting the test iteration"  $log_file_name | awk '{print $6}'`)
    res_TransactionType=(`grep "transaction type:"  $log_file_name| sed "s/transaction type://"|sed "s/ //"|sed "s/ /_/g"`)
    res_ScalingFactor=(`grep "scaling factor:"  $log_file_name | awk '{print $3}'`)
    res_QueryMode=(`grep "query mode:"  $log_file_name | awk '{print $3}'`)
    res_Clients=(`grep "number of clients:"  $log_file_name | awk '{print $4}'`)
    res_Threads=(`grep "number of threads:"  $log_file_name | awk '{print $4}'`)
    res_Duration=(`grep "duration:"  $log_file_name| sed "s/duration: //"|sed "s/ //g"`)
    res_TotalTransaction=(`grep "number of transactions actually processed: "  $log_file_name | awk '{print $6}'`)
    res_AvgLatency=(`grep "latency average: "  $log_file_name | sed "s/latency average: //"|sed "s/ //g"`)
    res_StdDevLatency=(`grep "latency stddev: "  $log_file_name | sed "s/latency stddev: //"|sed "s/ //g"`)
    res_TPSIncConnEstablishing=(`grep "tps.*including connections establishing"  $log_file_name | awk '{print $3}'`)
    res_TPSExcludingConnEstablishing=(`grep "tps.*excluding connections establishing"  $log_file_name | awk '{print $3}'`)
    res_PgServer=(`grep  pgbench $log_file_name | sed "s_^.*postgres://__" | sed "s_:5432/postgres__"`)
    res_Duration=(`grep duration $log_file_name| awk '{print $2}'`)
    
    echo "Iteration,ScalingFactor,Clients,Threads,TotalTransaction,AvgLatency,StdDevLatency,TPSIncConnEstablishing,TPSExcludingConnEstablishing,TransactionType,QueryMode,Duration,PgServer,Duration"  > $csv_file

    count=0

    while [ "x${res_ScalingFactor[$count]}" != "x" ]
    do
        echo "${res_Iteration[$count]},${res_ScalingFactor[$count]},${res_Clients[$count]},${res_Threads[$count]},${res_TotalTransaction[$count]},${res_AvgLatency[$count]},${res_StdDevLatency[$count]},${res_TPSIncConnEstablishing[$count]},${res_TPSExcludingConnEstablishing[$count]},${res_TransactionType[$count]},${res_QueryMode[$count]},${res_Duration[$count]},${res_PgServer[$count]},${res_Duration[$count]}"  >> $csv_file
        ((count++))
    done

    total=$count

    avg_TPSIncConnEstablishing=`get_Avg "${res_TPSIncConnEstablishing[@]}"`
    avg_TPSExcludingConnEstablishing=`get_Avg "${res_TPSExcludingConnEstablishing[@]}"`

    minMax_TPSIncConnEstablishing=`get_MinMax "${res_TPSIncConnEstablishing[@]}"`
    minMax_TPSExcludingConnEstablishing=`get_MinMax "${res_TPSExcludingConnEstablishing[@]}"`

    TotalExecutionDuration=`get_Sum "${res_Duration[@]}"`
    DbInitializationDuration=`grep "tuples.*done" $log_file_name| tail -1| awk '{print $8 $9}'| sed s/,//`
    
    echo "" > $csv_file-tmp
    echo ",ServerDetails" >> $csv_file-tmp
    ServerVcores=`grep ${res_PgServer[0]} ConnectionProperties.csv | sed "s/,/ /g"| awk '{print $6}'`
    ServerName=`echo ${res_PgServer[0]} | sed "s/-pip.*//"`
    echo ",ServerVcores,$ServerVcores" >> $csv_file-tmp
    echo ",ServerName,$ServerName" >> $csv_file-tmp
    echo "" >> $csv_file-tmp
    echo ",,Min TPS,Max TPS,Average TPS" >> $csv_file-tmp
    echo ",TPSIncConnEstablishing,$minMax_TPSIncConnEstablishing,$avg_TPSIncConnEstablishing" >> $csv_file-tmp
    echo ",TPSExcludingConnEstablishing,$minMax_TPSExcludingConnEstablishing,$avg_TPSExcludingConnEstablishing" >> $csv_file-tmp
    echo "" >> $csv_file-tmp
    echo ",TotalExecutionDuration,$TotalExecutionDuration" >> $csv_file-tmp
    echo ",DbInitializationDuration,$DbInitializationDuration" >> $csv_file-tmp
    echo "" >> $csv_file-tmp
    
    cat $csv_file >> $csv_file-tmp
    mv $csv_file-tmp $csv_file

    echo $csv_file
}

function CSV2Html()
{
    CsvFileName=$1
    HtmlFileName=`echo $CsvFileName | sed "s/\.csv/\.html/"`
    cat $CsvFileName |sed "s/^,//g" |sed "s/ //g"  |awk -F"," 'BEGIN{    print "<table border="1">"}{
        print "<tr>";
        count=0
        for(i=1;i<=NF;i++){
            if($i == ""){
                count++
            }
            else{
                if(count!=0){
                    count++
                    print "<td colspan="count">"$i"</td>"
                    count=0
                }else{
                    print "<td>" $i"</td>";
                }            
            }       
        }
        print "</tr>"
    }END{print "</table>"}'  > $HtmlFileName
    echo $HtmlFileName
}

function SendMail ()
{
    MailBodyFile=$1
    Attachment=$2
    ReportEmail=$3

    echo "Sending Email Report to $ReportEmail with $Attachment"

    Subject='PG synthetic workload report: '`date +%F`
    mail  -a "From:Alfred" -a 'MIME-Version: 1.0' -a 'Content-Type: text/html; charset=iso-8859-1' -a 'X-AUTOR: Ing. Gareca' -s "$Subject" $ReportEmail -A $Attachment  < $MailBodyFile
}

function CopyToAzureStorageBlob ()
{
    FileToBeUploaded=$1
    StorageAccountUrl=$2
    DestinationKey=$3
    
    echo "FileToBeUploaded $FileToBeUploaded to $StorageAccountUrl$FileToBeUploaded with $DestinationKey"

    yes|azcopy --source $FileToBeUploaded --destination $StorageAccountUrl$FileToBeUploaded --dest-key $DestinationKey
}

function ParseAll()
{
    SummaryCsv="$log_folder/Summary.csv"

    list=(`ls $log_folder/*.log`)

    echo ",,ServerDetails,,,TPS Including Connection Establishment,,,TPS Excluding Connection Establishment,,,Test Parameters,,Execution Durations" >> $SummaryCsv
    echo ",Name,Vcores,Min TPS,Max TPS,Average TPS,Min TPS,Max TPS,Average TPS,ScalingFactor,Clients,Threads,TotalExecutionDuration,DbInitializationDuration" >> $SummaryCsv
    count=0
    while [ "x${list[$count]}" != "x" ]
    do
        echo "Parsing ${list[$count]}.."
        CsvFile=`Parse ${list[$count]}`
        ServerVcores=`grep ServerVcores $CsvFile | sed "s/,/ /g"| awk '{print $2}'`
        ServerName=`grep ServerName $CsvFile | sed "s/,/ /g"| awk '{print $2}'`
        TPSIncConnEstablishing=`grep TPSIncConnEstablishing $CsvFile | head -1 | sed "s/,TPSIncConnEstablishing,//g"`
        TPSExcludingConnEstablishing=`grep TPSExcludingConnEstablishing $CsvFile  | head -1 | sed "s/,TPSExcludingConnEstablishing,//g"`
        Params=`grep $ServerName $CsvFile | tail -1| sed "s/,/ /g"| awk '{print $2,$3,$4}'| sed "s/ /,/g"`
        TotalExecutionDuration=`grep TotalExecutionDuration $CsvFile| awk -F"," '{print $3}'`
        DbInitializationDuration=`grep DbInitializationDuration $CsvFile| awk -F"," '{print $3}'`
        echo ",$ServerName,$ServerVcores,$TPSIncConnEstablishing,$TPSExcludingConnEstablishing,$Params,$TotalExecutionDuration,$DbInitializationDuration" >> $SummaryCsv

        fileName=`basename $CsvFile`
        fileName=`echo $CsvFile |sed "s/$fileName/$ServerName\.csv/"`
        mv $CsvFile $fileName
        
        fileName=`basename ${list[$count]}`
        fileName=`echo ${list[$count]} |sed "s/$fileName/$ServerName\.log/"`
        mv ${list[$count]} $fileName

        ((count++))
    done

    htmlFile=`CSV2Html $SummaryCsv`
    
    mkdir -p $log_folder/CSVs
    mv $log_folder/*.csv $log_folder/CSVs/
    reportZipFile=`date|sed "s/ /_/g"| sed "s/:/_/g"`.zip
    zip -r $reportZipFile *.csv $log_folder/*

    StorageAccountUrl=`grep "StorageAccountUrl" $TestDataFile | sed "s/,/ /g"| awk '{print $2}'`
    DestinationKey=`grep "DestinationKey" $TestDataFile | sed "s/,/ /g"| awk '{print $2}'`
    ReportEmail=`grep "ReportEmail" $TestDataFile | sed "s/,/ /g"| awk '{print $2}'`

    SendMail $htmlFile $reportZipFile $ReportEmail
    
    CopyToAzureStorageBlob $reportZipFile $StorageAccountUrl $DestinationKey

    mv $reportZipFile OldLogs/
    
    echo "Parsing done!"
}

function CheckDependencies()
{
    if [ ! -f ConnectionProperties.csv ]; then
        echo "ERROR: ConnectionProperties.csv: File not found!"
        exit 1
    fi

    if [ ! -d $log_folder ]; then
        echo "ERROR: $log_folder: log_folder not found!"
        exit 1
    fi

    if [ $DEBUG == 0 ]
    then
        if [ ! -f  ClientDetails.txt ]; then
            echo "ERROR: ClientDetails.txt: File not found!"
            exit 1
        fi
    fi

    if [[ `which bc` == "" ]]; then
        echo "INFO: bc: not installed!"
        echo "INFO: bc: Trying to install!"
        apt install bc -y
    fi
    
    if [[ `dpkg -l | grep mailutils| wc -l` == "0" ]]; then
        echo "INFO: mailutils: not installed!"
        echo "INFO: mailutils: Trying to install!"
        apt-get install mailutils
    fi
}

###############################################################
##
##              Script Execution Starts from here
###############################################################
CheckDependencies

if [ $DEBUG != 0 ]
then
    log_folder=$1
    if [ "$#" -ne 1 ]; then
        echo "Usage: $0 <path to pgbench logs>" >&2
        exit 1
    fi
    ParseAll
    exit 1
fi  
log_folder=`date|sed "s/ /_/g"| sed "s/:/_/g"`
mkdir -p $log_folder
echo "Getting logs from clients.."
TestDataFile='ConnectionProperties.csv'

res_ClientDetails=$(`cat $TestDataFile | sed "s/,/ /g"| awk '{print $7}'`)

count=1
while [ "x${res_ClientDetails[$count]}" != "x" ]
do
    ssh ${res_ClientDetails[$count]} 'hostname' 
    ssh  ${res_ClientDetails[$count]} "bash /home/orcasql/W/RunTest.sh"
    scp ${res_ClientDetails[$count]}:/home/orcasql/W/Last* $log_folder/ 
    ((count++))
done
echo "Getting logs from clients.. done!"    

ParseAll

if [ ! -d OldLogs ]; then
    mkdir -p OldLogs
fi

mv $log_folder OldLogs/$log_folder
