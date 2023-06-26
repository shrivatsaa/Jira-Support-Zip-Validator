#!/bin/sh

usage="script usage: $0 -p <Product(optional)> <folderName> <Date(optional)>";

FolderPath=""
checkdate=""
Product=""
ProductHeader=""
ProductChosen=""
ErrorAvail=0
red=$'\e[1;31m'
green=$'\e[1;32m'
blue=$'\e[1;34m'
white=$'\e[0m'
magenta=$'\e[1;35m'
combo=$'\e[3;4m'
cyan=$'\e[1;36m'
bold=$(tput bold)
normal=$(tput sgr0)


if [ $# -eq 0 ] ; then
  echo "$usage";
  exit 1;
fi 

if [[ "$OSTYPE" = "linux-gnu"* ]]; then 
  sedvar='-e'
elif [[ "$OSTYPE" = "darwin"* ]]; then
  sedvar=''
else
  sedvar='-e'
fi

if ! which jq >/dev/null; then echo "$red You do not have \"jq\" installed. Will skip DBR and perfmance log stats. Otherwise please install from https://stedolan.github.io/jq/download/ and rerun.$white";
 jqOut="NOTINSTALLED";
fi

while getopts "fp:dh" opt; do
  case "$opt" in
    f)
      FolderPath="$OPTARG"
      ;;
    p)
      ProductChosen="$OPTARG"
      ;;
    d)
      checkdate="$OPTARG"
      ;;
    h) 
      echo "$usage : -p(optional) can take values of 'JSW','Perf','JSM','Insight','Roadmaps'" 
      exit 1
      ;;
    ?)
      echo "$usage"; 
      ;;
  esac
done
shift "$((OPTIND-1))" 

FolderPath=$1;
if [[ ! -d "$FolderPath" ]] ; then
{
  echo "$usage";
  echo "$blue\nCould not find the provided folder. Please check the path\n$white";

  exit 1;
}
fi

#List of vars to be used across functions globally
Logpath=$FolderPath;
HealthcheckFile=$FolderPath/healthchecks/healthcheckResults.txt
ApplicationLogPath=$FolderPath/application-logs/
CatalinalogPath=$FolderPath/tomcat-logs/
GcLogPath1=$FolderPath/application-logs/
GcLogPath2=$FolderPath/tomcat-logs/

#Suggestion list array, takes values of 1,2 and 3 for minor, major and critical errors
SuggestionArr=("FirstElement|0")
MaxFileDesc=""
PoolMax=""

#Get the date if give or assign to the current date
if [[ $2 != "" ]] ; then {
  checkdate=$2
} 
else {
  checkdate=$(date +"%Y-%m-%d")
}
fi

if [[ -f $Logpath/verifier.txt ]] ; then
{
  rm $Logpath/verifier.txt > /dev/null;
} 
fi

echo "$blue\nIf you want choose a specific product to analyze with -p option, these are the valid values for -p : JSW,Perf,JSM,Insight,Roadmaps.\n$white";

#List of messages to look for in the application log and corresponding suggestion. This array will be used if LogErrorData.txt file is lost or not available
messages=(
"java.lang.StackOverflowError|Look out for stuck threads and application stalling. Refer https://confluence.atlassian.com/jirakb/jira-applications-stall-due-to-stackoverflowerror-exception-941601100.html"
"Wait attempt timed out - waited|Look out for indexing and snapshot restore failures. Also look for nodereindexing threads or clustermessagehandler threads timing out waiting for index lock"
"Bigpipe taking longer than 5s|Look out for cpu usage and other performance issues."
"There was an error getting a DBCP datasource|Verify any connection errors, stuck threads, full GCs or system resource overrun. Refer https://confluence.atlassian.com/adminjiraserver073/surviving-connection-closures-861253055.html"
)

#Lookup Table used for defining the product type and the corresponding header defined in the LogDataerror.txt file.
LookupArr=(JSW=JSW_Log_Messages Perf=Performance_Log_Messages JSM=JSM_Log_Messages Insight=Insight_Log_Messages Roadmaps=Advanced_RoadMaps)


for ((i=0;i<${#LookupArr[*]};i++));
do
  #Get the Product name from the lookup array
  Product=$(echo ${LookupArr[$i]} | awk -F "=" '{print $1}');
  if [[ $Product == $ProductChosen ]] ; then
  {
    #Get the product header to be compared as defined in the LogDataerror.txt
    ProductHeader=$(echo ${LookupArr[$i]} | awk -F "=" '{print $2}');
  }
  fi
done

#Incase no product is chosen, verify for the JSW messages in atlassian-jira.log
if [[ $ProductHeader == "" ]] ; then
{
  #Get the product header to be compared as defined in the LogDataerror.txt
  ProductHeader="Performance_Log_Messages";
}
fi

#Validate the health check results
ValidateHealthCheck()
{
  printf $combo'List of healtcheck failures : \n'$white | tee -a $Logpath/verifier.txt; 
  if [[ -f $HealthcheckFile ]] ; then {
    awk -v RS="" -v ORS="\n\n" '/Is healthy: false/{print}' $HealthcheckFile | awk -v RS="\n\n" -v FS="\n" '{for(i=1;i<=NF;i++){if($i~/Name/){key1=$i} else if($i~/Failure/){key2=$i}}{print key1" ----> "key2}}'
    printf "\n";
    if [[ $(grep -c "Is healthy: false" $HealthcheckFile) -gt 0 ]] ; then
      {
        SuggestionArr+=("Review_HealthCheck_Failures|1");
      }
    fi
  }
  else 
  {
    echo  $cyan'No healthcheck file found under healtchecks folder. Skipping healthchecks\n'$white | tee -a $Logpath/verifier.txt;
  }
  fi
}


#Validate the GC log for full GCs.
ValidateGCLog()
{
  NumofGCFiles=$(ls $GcLogPath1/*gc* 2>/dev/null | wc -l);
  if [[ NumofGCFiles -gt 0 ]] ; then {
     GCFilePath=$GcLogPath1;
  }
  fi

  NumofGCFiles=$(ls $GcLogPath2/*gc* 2>/dev/null | wc -l);
  if [[ NumofGCFiles -gt 0 ]] ; then {
     GCFilePath=$GcLogPath2;
  }
  fi   
    
  printf $combo'\nFull GC details from the past 4 GC files:\n'$white | tee -a $Logpath/verifier.txt;
  if [[ $GCFilePath != "" ]] ; then {
    #Check for Full GCs in the GC files for past 6 days only.
    GCfiles=($(ls -lt $PWD/$GCFilePath/*gc* | head -20 | awk '{print $NF}'));   
    if [[ "$GCfiles" =~ ^(\/.+)$ ]]; then { 
      GCcount1=$(grep -h "$checkdate.*Full GC\|$checkdate.*Pause Full" "${GCfiles[@]}" | grep -c -v "Metadata GC Threshold\|gc,start");
      if [[ $GCcount1 -gt 0 ]] ; then {  
        SuggestionArr+=("Full_GC_Incident_$checkdate|3");
        Interval=$(grep -h "$checkdate.*Full GC\|$checkdate.*Pause Full" "${GCfiles[@]}" | grep -v "Metadata GC Threshold\|gc,start" | sort -nk1 | sed 's/\[//g' | awk 'NR==1;END{print}' |  awk -F "+" '{print $1}' | awk -F"-|T" '{print $4}' | awk -v StartTime="" -v EndTime="" '{StartTime=$0;getline;EndTime=$0;print StartTime " and " EndTime}');
        echo $green"$GCcount1 instances of $white $red Full GCs $white $green found on $checkdate in the timeperiod $white $blue $Interval.\n"$white | tee -a $Logpath/verifier.txt;
      }
      else 
      {
        echo $green"No Full GCs were found for today or given date.\n"$white | tee -a $Logpath/verifier.txt;
      }
      fi
      
      GCcount2=$(grep -h ".*Full GC\|.*Pause Full" "${GCfiles[@]}"  | grep -c -v "Metadata GC Threshold\|gc,start");
      if [[ $GCcount2 -gt 0 && $GCcount2 != $GCcount1 ]] ; then {
        SuggestionArr+=("Past_Full_GC_Incidents|2");  
        GCDates=($(grep -h ".*Full GC\|.*Pause Full" "${GCfiles[@]}" | grep -v "Metadata GC Threshold\|gc,start\|$checkdate" | awk -F "T" '{print $1}' | sed -e 's/\[//g' | sort | uniq)); 
        #Get the full GC count and interval for each date in the past four days
        for dates in "${GCDates[@]}"; do printf "%s %s %s\n" "$dates" "$(grep -h "$dates.*Full GC\|$dates.*Pause Full" "${GCfiles[@]}" | grep -c -v "Metadata GC Threshold\|gc,start\|$checkdate")" "$(grep -h "$dates.*Full GC\|$dates.*Pause Full" ${GCfiles[@]} | grep -v "Metadata GC Threshold\|gc,start" | sed 's/\[//g' | awk 'NR==1;END{print}' |  awk -F "+" '{print $1}' | awk -F"-|T" '{print $4}' | awk -v StartTime="" -v EndTime="" '{StartTime=$0;getline;EndTime=$0;print StartTime "--->" EndTime}')" ; done | awk '{print $2 " Full GCs found on " $1 " between " $3}'
        printf "\n"
      }
      fi      
    }
    fi
    
    if [[ $GCcount1 -eq 0 && $GCcount2 -eq 0 ]] ; then 
    {
         echo $green"No Full GCs were found in the provided GC logs in the past 4 GC files.\n"$white | tee -a $Logpath/verifier.txt;
    }
    fi
  }  
  else 
  {
    echo $cyan'No GC files of type atlassian-jira-gc found either in tomcat-logs or application-logs. Skipping GC checks\n'$white | tee -a $Logpath/verifier.txt;
  }
  fi
}

#Validate the Application log for errors.
ValidateAppLog()
{
  printf $combo'\nApplication log contains following errors : \n'$white | tee -a $Logpath/verifier.txt; 
  if [[ -f $ApplicationLogPath/atlassian-jira.log ]] ; then {
    if [[ -f LogErrorData.txt ]] ; then {
      #Get the number of occurrences of different errors in the application log for the past 6 files
      Appfiles=($(ls -lt $PWD/$ApplicationLogPath/*atlassian-jira.log* | head -6 | awk '{print $NF}'));
      if [[ "$Appfiles" =~ ^(\/.+)$ ]]; then {

        #We create temp file since using read line after pipe opens a new subshell and all variable assignment is lost.
        awk "/$ProductHeader/"'{p=1;next}'"/ProductSeparator/"'{p=0}p' LogErrorData.txt > tempfile
        #Check for errors of different types found in the the LogErrorData.txt file for the chosen product.
        while read line
        do
          #Get the error message
          error=$(echo $line | awk -F"|" '{print $1}');
          #Get the suggestion message
          Suggestion=$(echo $line | awk -F"|" '{print $2}');

          #Get the number of occurrences of different errors based on date
          count=$(grep -c -h "$checkdate.*$error" "${Appfiles[@]}" | awk '{sum+=$1}END{print sum}');
          if [[ $count -gt 0 ]] ; then {
            ErrorPrint=$(echo $error | sed 's/ /_/g');
            SuggestionArr+=("$ErrorPrint|4");
            echo $green"$count instances of errors of type$white $red $error $white $green found on $checkdate.$white $blue $Suggestion\n"$white | tee -a $Logpath/verifier.txt;
            ErrorAvail=1;
          }
          #check again without the date filter and report the errors seen
          else 
          {
            count=$(grep -c -h "$error" "${Appfiles[@]}" | awk '{sum+=$1}END{print sum}');
            if [[ $count > 0 ]] ; then {
              ErrorPrint=$(echo $error | sed 's/ /_/g');
              SuggestionArr+=("$ErrorPrint|4");
              echo $green"$count Errors of type$white $red $error $white $green found, but not on today or given date.$white $blue $Suggestion\n"$white | tee -a $Logpath/verifier.txt;  
              ErrorAvail=1;
            } 
            fi
          }  
          fi
        done < tempfile
        rm tempfile
      }
      fi
      if [[ $ErrorAvail -eq 0 ]] ; then {
         echo $green"Found no errors based on the list of errors in the messages variable in the script or LogErrorData.txt. Verify application logs for other errors or update script with more data for future.\n"$white | tee -a $Logpath/verifier.txt;
      }
      fi
    }
    else 
    {
      #Look for some messages to grep for from the messages array. 
      for ((i=0;i<${#messages[*]};i++));
      do
         #Get the error message
         error=$(echo ${messages[$i]} | awk -F"|" '{print $1}');
         #Get the suggestion message
         Suggestion=$(echo ${messages[$i]} | awk -F"|" '{print $2}');

         #Get the number of occurrences of different errors based on date
         Appfiles=($(ls -lt $PWD/$ApplicationLogPath/*atlassian-jira.log* | head -6 | awk '{print $NF}'));
         if [[ "$Appfiles" =~ ^(\/.+)$ ]]; then {
           count=$(grep -c -h "$checkdate.*$error" "${Appfiles[@]}" | awk '{sum+=$1}END{print sum}');
           if [[ $count -gt 0 ]] ; then 
            {
              ErrorPrint=$(echo $error | sed 's/ /_/g');
              SuggestionArr+=("$ErrorPrint|4");
              echo $green"$count instances of errors of type$white $red $error $white $green found on $checkdate.$white $blue $Suggestion\n"$white | tee -a $Logpath/verifier.txt;
              ErrorAvail=1;
            }
            #check again without the date filter and report the errors seen
            else 
            {
              count=$(grep -c -h "$error" "${Appfiles[@]}" | awk '{sum+=$1}END{print sum}');
              if [[ $count -gt 0 ]] ; then {
                ErrorPrint=$(echo $error | sed 's/ /_/g');
                SuggestionArr+=("$ErrorPrint|4");
                echo $green"$count Errors of type$white $red $error $white $green found, but not on today or given date.$white $blue $Suggestion\n"$white | tee -a $Logpath/verifier.txt;
                ErrorAvail=1;  
              }
              fi
            }  
            fi
         }
         else 
         {
           echo $green"Found no application files to parse for error messages. Skipping application error checks. \n"$white | tee -a $Logpath/verifier.txt;
           return;
         }
         fi
      done    
      if [[ $ErrorAvail -eq 0 ]] ; then {
         echo $green"Found no errors based on the list of errors for $ProductHeader in the messages variable in the script. Verify application logs for other errors or update script with more data for future.\n"$white | tee -a $Logpath/verifier.txt;
      }
      fi
    }
    fi   
  }
  else 
  {
    echo $cyan'No application log of format atlassian-jira.log found. Skipping application log checks\n'$white | tee -a $Logpath/verifier.txt;
  }
  fi
}


ValidateCatalina()
{
  ErrorAvail=0;
  printf $combo'Checking stuck threads or memory issues in catalina.out : \n'$white | tee -a $Logpath/verifier.txt; 
  if [[ -f $CatalinalogPath/catalina.out ]] ; then 
  {
    CatFile="catalina.out";
    maxsize=50000000;
    CatalinaFileSize=$(stat -f%z "$CatalinalogPath/catalina.out")

    #Check if the file size is greater than 50MB then avoid parsing it and split them to smaller chunks
    if (( $CatalinaFileSize > $maxsize ))  ; then 
    {
      split -b 50000000 $CatalinalogPath/catalina.out $CatalinalogPath/Sega;
      ShortFileName=$(ls -l $CatalinalogPath/*Sega* | tail -1 | awk '{print $NF}');

      #Check if the smallest file among the split files is less than 10mb, then abridge last two files to get enough data
      if (( $(stat -f%z $ShortFileName) < 10000000 )) ; then 
      {
        NewFile=($(ls -l $CatalinalogPath/*Sega* | tail -2 | awk '{print $NF}' | awk '{file1=$0;getline;file2=$0;print file1 " " file2}'));
        cat "${NewFile[@]}" > $CatalinalogPath/NewCatFile.out;
        CatFile="NewCatFile.out";
        rm $CatalinalogPath/*Sega*
      }
      else
      {
        mv $ShortFileName $CatalinalogPath/CatalinaSmall.out;
        rm $CatalinalogPath/*Sega*
        CatFile="CatalinaSmall.out";
      }
      fi
    }
    fi
    HeapSpaceCount=$(grep -c "java.lang.OutOfMemoryError: Java heap space" $CatalinalogPath/$CatFile);
    if [[ $HeapSpaceCount -gt 0 ]] ; then {    
      SuggestionArr+=("java.lang.OutOfMemoryError|3");       
      echo $green"Errors of type $red java.lang.OutOfMemoryError: Java heap space $white $green were found. $white $blue Please verify if its valid for the current date\n"$white | tee -a $Logpath/verifier.txt;  
      ErrorAvail=1;
    }
    fi
    OutOfMemoryErrorCount=$(grep -c "Dumping heap to" $CatalinalogPath/$CatFile);
    if [[ $OutOfMemoryErrorCount -gt 0 ]] ; then {
      HeapLoc=$(grep "Dumping heap to" $CatalinalogPath/$CatFile | awk '{for(i=1;i<=NF;i++){if ($i ~ /\//){print $i}}}');
      SuggestionArr+=("HeapFile:$HeapLoc|3");  
      echo $green"We see $red Heap dumps have been generated in $HeapLoc. $white $blue Please verify if its valid for the current date from catalina.out.\n"$white | tee -a $Logpath/verifier.txt;
      ErrorAvail=1;
    } 
    fi
    TDumpCount=$(grep -c "JNI global references" $CatalinalogPath/$CatFile);
    if [[ $TDumpCount -gt 0 ]] ; then {
      echo $green"Threads dumps seem to have been generated. Parsing thread dumps from catalina.out now and placing it in current directory. $white $blue Please verify if its valid for the current date\n"$white | tee -a $Logpath/verifier.txt;
      awk '/^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$/{n++;td=1;lastLine=$0;outFile=("thread_dump_" n ".txt")}; {if (td) {print $0 >> outFile; close(outFile)}}; /JNI global references/{if (lastLine ~ /garbage-first/ || lastLine ~ /Metaspace/) {td=0}}' $CatalinalogPath/catalina.out
      ErrorAvail=1;
    }   
    fi 
    Finddate=$(date +"%Y-%m-%d")
    StuckThreadCount=$(grep $Finddate.*org.apache.catalina.valves.StuckThreadDetectionValve.notifyStuckThreadDetected $CatalinalogPath/$CatFile | awk '{print $(NF-13)}' | sed -e 's/\[//g' -e 's/\]//g' | awk '{if ($0>max) max=$0}END{print max}');
    if [[ $StuckThreadCount -gt 10 ]] ; then {
      SuggestionArr+=("Stuck_Threads_in_Catalina|2");
      echo $green"Found $red $StuckThreadCount stuck threads $white $green at some point of time today as per StuckThreadDetectionValve. $white $blue Please verify if its valid for the current date from catalina.out\n"$white | tee -a $Logpath/verifier.txt;
      ErrorAvail=1;
    }
    fi
    if [[ $ErrorAvail -eq 0 ]] ; then {
      echo $green"Found no heap dump or our of memory or stuck threads and thread dumps in catalina.out. Verify individually for further issues.\n"$white | tee -a $Logpath/verifier.txt;
    }
    fi
  }
  else
  {
    echo $green'No Catalina.out found in under $CatalinalogPath. Skipping Catalina.out log checks\n'$white | tee -a $Logpath/verifier.txt; 
  }
  fi
}

ValidateInstDetails()
{
  printf $combo'Instance Details : \n'$white | tee -a $Logpath/verifier.txt;  
  if [[ -f $FolderPath/application-properties/application.xml ]] ; then {
  
  #Parse the application.xml file for JVM arguments

  JiraVersion=$(grep -o "<Version>.*</Version>" $FolderPath/application-properties/application.xml | sed -e "s/<Version>//g" -e "s/<\/Version>//g" | tr ' ' '\n');
  echo "\n$bold Jira Version $normal : $JiraVersion" | tee -a $Logpath/verifier.txt;

  NumOfProcs=$(grep -o "<available-processors>.*</available-processors>" $FolderPath/application-properties/application.xml | sed -e "s/<available-processors>//g" -e "s/<\/available-processors>//g" | tr ' ' '\n');
  echo "$bold Number of Processors $normal : $NumOfProcs" | tee -a $Logpath/verifier.txt;

  TotalPhysMem=$(grep -o "<total-physical-memory>.*</total-physical-memory>" $FolderPath/application-properties/application.xml | sed -e "s/<total-physical-memory>//g" -e "s/<\/total-physical-memory>//g" | tr ' ' '\n');
  echo "$bold Total Physical Memory $normal : $TotalPhysMem" | tee -a $Logpath/verifier.txt;

  NumOfIssues=$(grep -o "<Issues>.*</Issues>" $FolderPath/application-properties/application.xml | sed -e "s/<Issues>//g" -e "s/<\/Issues>//g" | tr ' ' '\n');
  echo "$bold Number of Issues $normal : $NumOfIssues" | tee -a $Logpath/verifier.txt; 
   
  MaxFileDesc=$(grep -o "<max-file-descriptor>.*</max-file-descriptor>" $FolderPath/application-properties/application.xml | sed -e "s/<max-file-descriptor>//g" -e "s/<\/max-file-descriptor>//g" -e "s/,//g" | tr ' ' '\n');
  echo "$bold Max File Descriptor $normal : $MaxFileDesc" | tee -a $Logpath/verifier.txt; 

  NumOfCustFields=$(grep -o "<Custom-Fields>.*</Custom-Fields>" $FolderPath/application-properties/application.xml | sed -e "s/<Custom-Fields>//g" -e "s/<\/Custom-Fields>//g");
  echo "$bold Number of Custom Fields $normal : $NumOfCustFields" | tee -a $Logpath/verifier.txt; 

  NumOfGroups=$(grep -o "<Groups>.*</Groups>" $FolderPath/application-properties/application.xml | sed -e "s/<Groups>//g" -e "s/<\/Groups>//g");
  echo "$bold Number of Groups $normal : $NumOfGroups" | tee -a $Logpath/verifier.txt; 

  NumOfUsers=$(grep -o "<Users>.*</Users>" $FolderPath/application-properties/application.xml | sed -e "s/<Users>//g" -e "s/<\/Users>//g");
  echo "$bold Number of Users $normal : $NumOfUsers" | tee -a $Logpath/verifier.txt; 

  JVMMemory=$(grep -o "<Total-Memory>.*</Total-Memory>" $FolderPath/application-properties/application.xml | sed -e "s/<Total-Memory>//g" -e "s/<\/Total-Memory>//g");
  echo "$bold Total JVM Memory $normal : $JVMMemory" | tee -a $Logpath/verifier.txt; 

  JVMArgs=$(grep -o "<JVM-Input-Arguments>.*</JVM-Input-Arguments>" $FolderPath/application-properties/application.xml | sed -e "s/<JVM-Input-Arguments>//g" -e "s/<\/JVM-Input-Arguments>//g");
  if [[ $(echo $JVMArgs | grep "HeapDumpOnOutOfMemoryError") == "" ]] ; then 
    {
      SuggestionArr+=("Add_HeapDumpOnOutOfMemoryError_to_jvmargs|2");
    }
  fi
  echo "$bold JVM Attributes $normal : $JVMArgs" | tee -a $Logpath/verifier.txt; 

  AnnouncementBanner=$(grep -o "<jira.alertheader>.*</jira.alertheader>" $FolderPath/application-properties/application.xml | sed -e "s/<jira.alertheader>//g" -e "s/<\/jira.alertheader>//g");
  if [[ $(echo $AnnouncementBanner | grep "script") != "" ]] ; then 
    {
      SuggestionArr+=("AnnouncementBanner_has_Scripts|2");
    }
  fi
  printf "\n";
  }
else
  {
    echo $green'No application.xml found under application-properties folder. Skipping instance checks\n'$white | tee -a $Logpath/verifier.txt;   
  }
  fi

  if [[ -f $FolderPath/application-config/dbconfig.xml ]] ; then 
  {
    DBType=$(grep -o "<database-type>.*</database-type>" $FolderPath/application-config/dbconfig.xml | sed -e "s/<database-type>//g" -e "s/<\/database-type>//g" | tr ' ' '\n');
    echo "$bold Database Type $normal : $DBType" | tee -a $Logpath/verifier.txt; 

    PoolMax=$(grep -o "<pool-max-size>.*</pool-max-size>" $FolderPath/application-config/dbconfig.xml | sed -e "s/<pool-max-size>//g" -e "s/<\/pool-max-size>//g" | tr ' ' '\n');
    echo "$bold Pool Max Size $normal : $PoolMax" | tee -a $Logpath/verifier.txt; 

    DBUrl=$(grep -o "<url>.*</url>" $FolderPath/application-config/dbconfig.xml | sed -e "s/<url>//g" -e "s/<\/url>//g" | tr ' ' '\n');
    echo "$bold Database Url $normal : $DBUrl" | tee -a $Logpath/verifier.txt;      
  }
  fi

}

ValidateThreadDumps()
{
  printf $combo'Thread dump analysis from thread dumps folder\n'$white | tee -a $Logpath/verifier.txt;  
  TDumpFolderPost9=$(Find $PWD/$FolderPath -name "threaddumps");
  TDumpFolderPre9=$(Find $PWD/$FolderPath -name "thread-dump");
  if [[ "$TDumpFolderPost9" =~ ^(\/.+)$ ]]; then
  {
    TDumpFolder=$TDumpFolderPost9;
    printf $green'Running http Thread overview for last 4 dumps from JFR \n'$white | tee -a $Logpath/verifier.txt; 
  }
  elif [[ "$TDumpFolderPre9" =~ ^(\/.+)$ ]]; then
    {
    TDumpFolder=$TDumpFolderPre9;
    printf $green'Running http Thread overview for last 4 dumps from support tool \n'$white | tee -a $Logpath/verifier.txt;
  }
  else {
    echo $green'Thread dumps not collected in support zip. Skipping thread dump analysis\n'$white | tee -a $Logpath/verifier.txt;
    return;
  }
  fi

  #Gather the last 5 thread dump files excluding the cpu utilization : Modify the tail command below to increase/decrease the number of files to be analysed
  TDumpFiles=(`ls $TDumpFolder | awk '{print $NF}' | grep -v "thread_cpu_utilisation" | tail -4`);
  if [[ "${#TDumpFiles[*]}" != 0 ]] ; then
  {
    ThreadFiles=($(for filename in "${TDumpFiles[@]}"; do awk '{if ($0~/java.lang.Thread.State/){print FILENAME;exit}}' $TDumpFolder/$filename ; done));
    ThreadTimes=$(for var in "${ThreadFiles[@]}"; do awk -v ORS="|" 'NR==1{print $2}' $var; done);
  }
  else {
    echo $green'Thread dump files not found in the'$white $TDumpFolder $green'. Skipping thread dump analysis\n'$white | tee -a $Logpath/verifier.txt;
    return;
  }
  fi

  #Now gather the thread details with user and request information.
  grep -h "http-nio.*exec" "${ThreadFiles[@]}" | grep -v "owned by" | awk '{for(i=1;i<=NF;i++){if($i ~ /http-nio.*exec/) printf "%s ",$i; else if($i=="url:") printf "%s ",$(i+1); else if ($i=="user:") printf "%s",$(i+1);}printf "\n"}' | awk -v User="" -v Url="" '{($3=="") ? User="NA" : User=$3 ;($2=="") ? Url="NA" : Url=$2 }{print $1,Url,User}' | awk '$2!="NA" || $3!="NA"{print}' | sed -e 's/"//g' -e 's/;//g' | sort -k1 | uniq | while read line; \
  do printf "|%s" "$(echo $line | awk '{print $3"|"$2}')"; PrintVar=$(echo $line |awk '{print $1}'); printf "||%s|%s\n" "$PrintVar" "$(gawk "/\y$PrintVar\y/"'{getline;getline;print}' "${ThreadFiles[@]}" | awk '{$1=$1};1' | sed -e 's/\(.*\)(.*)/\1/g' -e 's/at\ //g' | gawk -v FS="\n" -v OFS="|" -v RS="||" '{for(i=1;i<=NF;i++){printf "%s|", $i}}')"; done | sed 's/||/|/g' | gawk -v TimeOfThread="$ThreadTimes" 'BEGIN {print "|Username","|Request","|Thread_Name|",TimeOfThread}{print}' | column -t -s "|"  
  printf "\n"; 

  Requests=($(grep -h "http.*exec.*url" "${ThreadFiles[@]}" | awk '{for(i=1;i<=NF;i++){if($i ~ /url/){print $(i+1)}}}' | sort | uniq -c | sort -nrk1 | head -5 | awk '{print $1":"$2}'));
  Users=($(grep -h "http.*exec.*url" "${ThreadFiles[@]}" | awk '{for(i=1;i<=NF;i++){if($i ~ /user/){print $(i+1)}}}' | sort | uniq -c | sort -nrk1 | head -5 | awk '{print $1":"$2}')); 
  if [[ "${#Requests[*]}" -gt 0 && "${#Users[*]}" -gt 0 ]] ; then 
  {
    if (( "${#Requests[*]}" >= "${#Users[*]}" )) ; then
    {
      Iter=${#Requests[*]};
    }
    else
    {
      Iter=${#Users[*]};
    }
    fi
    
    echo $green'Top 5 requests and users in the thread dumps\n'$white | tee -a $Logpath/verifier.txt;
    for ((i=0;i<Iter;++i));do printf "%s|%s\n" "${Requests[$i]}" "${Users[$i]}" ; done | awk 'BEGIN{printf "\x1b[32m%s | %s\x1b[0m\n","Top_5_Requests","Top_5_Users"}{print}' | column -t -s "|"
  }
  fi

  #Check on the object monitor locks and threads wating on these locks.
  locks=($(awk -v RS='' -v ORS='\n\n' '/http.*exec/ && /parking to wait for/ || /waiting to lock/{print}' "${ThreadFiles[@]}" | grep "parking to wait for\|waiting to lock" | grep -v "java.util.concurrent.locks.AbstractQueuedSynchronizer" | egrep -oE "<0x.*>\ (.*)" | sed -e 's/<//g' -e 's/>//g' -e 's/(//g' -e 's/)//g'| sort | uniq -c | sort -nrk1 | head -5 | awk '{print $2"-"$NF}'));
  if [[ ${#locks[*]} -gt 0 ]] ; then 
  {
    echo $green'\nTop 5 object monitor locks and threads waiting on those locks\n'$white | tee -a $Logpath/verifier.txt;
    for var in "${locks[@]}";do pattern=$(echo $var | awk -F "-" '{print $1}'); printf "\n%s %s\n%s\n%s %s\n\n" "Following_Threads_waiting_on_this_lock:" "$(echo $var | awk -F "-" '{print "<"$1">","("$2")"}')" "$(gawk -v RS='' -v ORS='\n\n' "/waiting to lock.*$pattern/ && ! /locked.*$pattern/"'{print}' "${ThreadFiles[@]}" | awk 'NR==1;/^$/{getline;print}' | sort | uniq)" "$green'Locked by this thread:' $white" "$(gawk -v RS='' -v ORS='\n\n' "/locked.*$pattern/"'{print}' "${ThreadFiles[@]}" | awk 'NR==1;/^$/{getline;print}' | sort | uniq)" ; done 
  }
  fi

  #check on cpu utilization data if the files exist in JFR and if so print the utilization for the threads
  if (( $(Find $PWD/$FolderPath -name "*thread_cpu_utilisation*" | wc -l) > 1 )); then
  {
    echo $green'\nTThread and corresponding CPU usage percentage\n'$white | tee -a $Logpath/verifier.txt;
    cpufiles=(`ls $TDumpFolder | awk '{print $NF}' | grep "thread_cpu_utilisation" | tail -6`);
    CpuFilesDir=($(for filename in "${cpufiles[@]}"; do awk '{if ($0~/%CPU_USER_MODE/){print FILENAME;exit}}' $TDumpFolder/$filename ; done));
    CpuUsageColNum=$(awk 'NR==1{for(i=1;i<=NF;i++){a[$i]=i}}END{print a["%CPU_USER_MODE"]}' "${CpuFilesDir[1]}");
    ThreadNameColNum=$(awk 'NR==1{for(i=1;i<=NF;i++){a[$i]=i}}END{print a["THREAD_NAME"]}' "${CpuFilesDir[1]}"); 
    CpuFilesName=$(for var in "${cpufiles[@]}"; do printf "|%s" "$(echo $var|sed 's/_thread_cpu_utilisation.txt//g')"; done);
    awk -v Threadnamecol="$ThreadNameColNum" '{for(i=Threadnamecol;i<=NF;i++) printf "%s ",$i; printf "\n"}' "${CpuFilesDir[@]}" | grep -v "THREAD_NAME" | sort | uniq | while read line ; \
    do ThreadNameVar=$(echo $line | sed -e 's/\//\\\//g'); printf "||%s|%s\n" "$ThreadNameVar" "$(gawk -v col="$CpuUsageColNum" "/\y$ThreadNameVar\y/"'{print $col}' "${CpuFilesDir[@]}" | awk '{$1=$1};1' | gawk -v FS="\n" -v OFS="|" -v RS="||" '{for(i=1;i<=NF;i++){printf "%s|", $i}}' | gawk -v FS="\n" -v OFS="|" -v RS="||" '{for(i=1;i<=NF;i++){printf "%s|", $i}}')"; done | sed 's/||/|/g' | gawk -v files="$CpuFilesName" 'BEGIN {print "|Thread_Name",files}{print}' | column -t -s "|"
    printf "\n"; 
  }
  fi

}

ValidateDBRStats()
{

  printf $combo'\nRunning DBR(Document Based Replication) metrics analysis. Refer https://confluence.atlassian.com/jirakb/troubleshooting-performance-with-jira-stats-1041829254.html\n'$white | tee -a $Logpath/verifier.txt; 
  DBRfiles=($(ls -lt $PWD/$ApplicationLogPath/atlassian-jira.log* | head -4 | awk '{print $NF}'));  
  if [[ "$DBRfiles" =~ ^(\/.+)$ ]]; then
  {
    
    #Check if the get issue or increment issue version goes beyond threshold of 5ms and 10ms respectively.
    DBChecks=$(grep -h "$checkdate.*versioning-stats-0.*total" "${DBRfiles[@]}"  | awk '{printf "%s;%s|",$1,$2;{for(i=1;i<=NF;i++)if ($i ~ /getIssueVersionMillis/){print $i}}}' | jq -r -R 'select(contains("|"))|split("|")| "\(.[0]) \(.[1]|fromjson|to_entries[]|select(.key == "incrementIssueVersionMillis")|.value.avg)  \(.[1]|fromjson|to_entries[]|select(.key == "getIssueVersionMillis")|.value.avg)"' | awk '{if (($2>10) || ( $3>5 )){print}}' | sort -nk1 )    
    if [[ $DBChecks != "" ]] ; then
    {
      echo $green'\nDB read or DB update speed looks slower than usual in the following times.\n' $white | tee -a $Logpath/verifier.txt;
      for var in $DBChecks; do printf "%s\n" "$var"; done | awk 'BEGIN{print "Time","IncrementIssueVersion(~10)","GetIssueVersion(~5)"}{row1=$0;getline;row2=$0;getline;row3=$0; print row1,row2,row3}' | column -t
      SuggestionArr+=("DBR:Database_Read_or_Update_slow|1");
      DBRStatAvailable=1;
    }
    fi

    #Check if the time to add or send cache changes were delayed.
    CacheReplChecks=$(grep -h "$checkdate.*VIA-INVALIDATION.*total" "${DBRfiles[@]}"  | awk '{for(i=1;i<=NF;i++)if ($i ~ /timeToAddMillis/){print $i}}' | jq '. | [.timestampMillis, .nodeId , .timeToAddMillis.avg, .timeToSendMillis.avg] | @csv' | sed 's/"//g' | gawk -F "," '{if (($3>3) || ( $4>12 )){print strftime("%Y-%m-%d;%H:%M:%S",substr($1,1,10)),$2,$3,$4}}' | sort -nk1)
    if [[ $CacheReplChecks != "" ]] ; then
    {
      
      echo $green'\nTime to send cache changes or Disk speed were delayed in the following times .\n' $white | tee -a $Logpath/verifier.txt;
      for var in $CacheReplChecks; do printf "%s\n" "$var"; done | awk 'BEGIN{print "Time","Node","timeToAdd(Disk_speed~1ms)","timeToSend(Latency~10)"}{row1=$0;getline;row2=$0;getline;row3=$0;getline;row4=$0; print row1,row2,row3,row4}' | column -t
      SuggestionArr+=("DBR:CacheRepl_Add_or_Send_slow|2");
      DBRStatAvailable=1;
    }
    fi

    #Check if the time to send DBR message was delayed
    DBRReplChecks=$(grep -h "$checkdate.*TotalAndSnapshotDBRReceiverStats.*total" "${DBRfiles[@]}"  | awk '{printf "%s;%s|",$1,$2;{for(i=1;i<=NF;i++)if ($i ~ /receiveDBRMessage/){print $i}}}' | jq -r -R 'select(contains("|"))|split("|")| "\(.[0]) \(.[1]|fromjson|to_entries[]|select(.key == "receiveDBRMessageDelayedInMillis")|.value.avg) \(.[1]|fromjson|to_entries[]|select(.key == "processDBRMessageUpdateWithRelatedIndexInMillis")|.value.avg)"' | awk '{if (($2>110) || ( $3>40 )){print}}' | sort -nk1)    
    if [[ $DBRReplChecks != "" ]] ; then
    {
      
      echo $green'\nTime to receive DBR messages or process DBR messaages were delayed in the following times .\n' $white | tee -a $Logpath/verifier.txt;
      for var in $DBRReplChecks; do printf "%s\n" "$var"; done | awk 'BEGIN{print "Time","timeToReceiveDBR(NWLatency+LuceneQ~100)","TimeToProcessDBR(LuceneQ+Disk~30)"}{row1=$0;getline;row2=$0;getline;row3=$0; print row1,row2,row3}' | column -t
      SuggestionArr+=("DBR:DBR_Repl_slow|2");
      DBRStatAvailable=1;
    }
    fi

    #Check if adding DBR processed documents to lucene index was delayed
    DBR_Lucene_Checks=$(grep -h "$checkdate.*index-writer-stats-ISSUE.*total" "${DBRfiles[@]}" | awk '{printf "%s ",$2;{for(i=1;i<=NF;i++)if ($i ~ /addDocumentsMillis/){print $i}}}' | sed 's/,$//g' | awk '{printf "%s ",substr($1,1,8);print $2| "jq .updateDocumentsWithVersionMillis.avg";close("jq .updateDocumentsWithVersionMillis.avg")}' | awk '$2>15{print}' | sort -nk1)
    if [[ $DBR_Lucene_Checks != "" ]] ; then
    {
      
      echo $green'\nTime spent to conditionally add/update the index in the Lucene delayed in the following times.\n' $white | tee -a $Logpath/verifier.txt;
      for var in $DBR_Lucene_Checks; do printf "%s\n" "$var"; done | awk 'BEGIN{print "Time","TimeToAddToLucene(LuceneQ+Disk)"}{row1=$0;getline;row2=$0; print row1,row2}' | column -t
      SuggestionArr+=("DBR:DBR_AddLucene_slow|2");
      DBRStatAvailable=1;
    }
    fi

    if [[ $DBRStatAvailable -eq 0 ]] ; then {
      echo $green"Found no cache replication or DBR related issues.\n"$white | tee -a $Logpath/verifier.txt;
    }
    fi

  }
  fi

}

ValidatePerfLogStats()
{
  printf $combo'\nRunning jmx metrics analysis from the performance log\n'$white | tee -a $Logpath/verifier.txt;  

  if [[ -f $FolderPath/application-logs/atlassian-jira-perf.log ]] ; then 
  {

    #Check if the open files reaches 80% of the max file descriptor count
    Openfilecount=$(awk "/$checkdate.*JMXINSTRUMENTS-OS/"'{$1="";$2="";$3="";print}' $PWD/$FolderPath/application-logs/atlassian-jira-perf.log* | jq -r '.[]|[.timestamp,(.attributes[]|select(.name|contains("OpenFileDescriptorCount"))|.value)] | @tsv' | gawk -v maxfile="$MaxFileDesc" '$2>=(0.8*maxfile){print strftime("%Y-%m-%d;%H:%M:%S",$1),$1="",$0}')
    if [[ $Openfilecount != "" ]] ; then
    {
      echo $green'\nOpen Files reached 80% of the max open files configured in the following times. Verify if max open files should be increased.' $white | tee -a $Logpath/verifier.txt;
      for var in $Openfilecount; do printf "%s\n" "$var"; done | awk 'BEGIN{print "Time","OpenFile"}{row1=$0;getline;row2=$0; print row1,row2}' | column -t
      SuggestionArr+=("jmx:Openfiles_reached_80pct|1");
      PerfStatAvailable=1;
    }
  fi

    #Check for DB latency
    DBLatency=$(awk "/$checkdate.*DBLATENCY/"'{$1="";$2="";$3="";print}' $PWD/$FolderPath/application-logs/atlassian-jira-perf.log* | jq -r '.|[.timestamp,.latencyNanos] | @tsv' | awk '{print $1,$2/1000000}' | gawk '$2>3{print strftime("%Y-%m-%d;%H:%M:%S",$1),$1="",$0}');
    if [[ $DBLatency != "" ]] ; then
    {
      echo $green'\nDB latency reached more than 3ms in the following times. Verify if there are DB or network issues around those times.\n' $white | tee -a $Logpath/verifier.txt;
      for var in $DBLatency; do printf "%s\n" "$var"; done | awk 'BEGIN{print "Time","DBLatency(ms)"}{row1=$0;getline;row2=$0; print row1,row2}' | column -t
      SuggestionArr+=("jmx:DBlatency_morethan_3ms|1");
      PerfStatAvailable=1;
    }
    fi

    #check DBCP pool maxing
    DBCPMax=$(awk "/$checkdate.*PLATFORMINSTRUMENTS/"'{$1="";$2="";$3="";print}' $PWD/$FolderPath/application-logs/atlassian-jira-perf.log*  | jq -r '.|[.timestamp,(.instrumentList[]|select(.name|contains("dbcp.numActive"))|.value)] | @tsv'| gawk -v maxpool="$PoolMax" '$2>(0.90*maxpool){print strftime("%d-%m-%Y;%H:%M:%S",$1),$2,$3,$4}');
    if [[ $DBCPMax != "" ]] ; then
    {
      echo $green'\nDBCP pool reached 90% of the max pool size configured in the following times. Verify for any performance problems.' $white | tee -a $Logpath/verifier.txt;
      for var in $DBCPMax; do printf "%s\n" "$var"; done | awk 'BEGIN{print "Time","DBPool"}{row1=$0;getline;row2=$0; print row1,row2}' | column -t
      SuggestionArr+=("jmx:DBCP_pool_reached_90pct|1");
      PerfStatAvailable=1;
    }
    fi

    #check for process CPU load exceeding 90
    CpuLoad=$(parameter=".*Load.*";awk "/$checkdate.*JMXINSTRUMENTS-OS/"'{$1="";$2="";$3="";print}' $PWD/$FolderPath/application-logs/atlassian-jira-perf.log* | jq --arg param $parameter -r '.[]|[.timestamp,(.attributes[]|select(.name|test($param))|.value)] | @tsv' | gawk '{print strftime("%Y-%m-%d-%H:%M:%S",$1),$2,$3,$4}' | awk '$3>0.9{print}');
    if [[ $CpuLoad != "" ]] ; then
    {
      echo $green'\nCPU usage reached 90% in the following times. Verify for any performance problems.' $white | tee -a $Logpath/verifier.txt;
      for var in $CpuLoad;  do printf "%s\n" "$var"; done | awk 'BEGIN{print "Time","systemCPU","ProcessCPU","LoadAverage"}{row1=$0;getline;row2=$0;getline;row3=$0;getline;row4=$0;print row1,row2,row3,row4}' | column -t
      SuggestionArr+=("jmx:CPU_Usage_reached_90pct|1");
      PerfStatAvailable=1;
    }
    fi

    if [[ $PerfStatAvailable -eq 0 ]] ; then {
      echo $green"Found no issues with open files, DB latency or DBCP pool\n"$white | tee -a $Logpath/verifier.txt;
    }
    fi
  }
  else
  {
    echo $green'No perfomance log files found in the application-logs folder. Check log level in log4j.properties file. Skipping jmx metric checks.\n'$white | tee -a $Logpath/verifier.txt;   
  }
  fi
}


PrintSuggestions()
{
  printf "\n------------------------------------------------------------------------$combo List of suggestions for review $white-------------------------------------------------------------------------\n\n" | tee -a $Logpath/verifier.txt;
  #Gather Critical Suggestions first
  for value in "${SuggestionArr[@]}"
  do
     MsgCriticality=$(echo $value | awk -F "|" '{print $2}');
     if [[ MsgCriticality -eq 4 ]] ; then {
        AppMsgToPrint+=($(echo $value | awk -F "|" '{print $1}'));
      }
    elif [[ MsgCriticality -eq 3 ]] ; then {
        CritMsgToPrint+=($(echo $value | awk -F "|" '{print $1}'));
      }
    elif [[ MsgCriticality -eq 2 ]]; then {
        MajorCritMsgToPrint+=($(echo $value | awk -F "|" '{print $1}'));
      }   
    elif [[ MsgCriticality -eq 1 ]]; then {
        MinorCritMsgToPrint+=($(echo $value | awk -F "|" '{print $1}'));
      } 
    fi
  done
  
  if (( "${#CritMsgToPrint[*]}" >= "${#MajorCritMsgToPrint[*]}" )) && (( "${#CritMsgToPrint[*]}" >= "${#MinorCritMsgToPrint[*]}" )) && (( "${#CritMsgToPrint[*]}" >= "${#AppMsgToPrint[*]}" )) ; then {
    NumOfItems=${#CritMsgToPrint[*]};
  }
  elif (( "${#MajorCritMsgToPrint[*]}" >= "${#CritMsgToPrint[*]}" )) && (( "${#MajorCritMsgToPrint[*]}" >= "${#MinorCritMsgToPrint[*]}" )) && (( "${#MajorCritMsgToPrint[*]}" >= "${#AppMsgToPrint[*]}" )) ; then {
    NumOfItems=${#MajorCritMsgToPrint[*]};
  }
  elif (( "${#MinorCritMsgToPrint[*]}" >= "${#CritMsgToPrint[*]}" )) && (( "${#MinorCritMsgToPrint[*]}" >= "${#MajorCritMsgToPrint[*]}" )) && (( "${#MinorCritMsgToPrint[*]}" >= "${#AppMsgToPrint[*]}" )) ; then {
    NumOfItems=${#MinorCritMsgToPrint[*]};
  }
  else {
    NumOfItems=${#AppMsgToPrint[*]};
  }
 fi
  
  #Print the suggestions togther." 
  for ((i=0; i<NumOfItems; ++i)); do
    if [[ i -eq 0 ]] ; then
    {
      printf "%s\t %s\t %s\t %s\n" "$combo'Critical_Suggestions'$white" "$combo'Major_Suggestions'$white" "$combo'Minor_Suggestions'$white" "$combo'Applog_Suggestions'$white" | tee -a $Logpath/verifier.txt;
    }
    fi
  printf "%s\t %s\t %s\t %s\n" "$red${CritMsgToPrint[$i]}$white" "$blue${MajorCritMsgToPrint[$i]}$white" "$green${MinorCritMsgToPrint[$i]}$white" "$magenta${AppMsgToPrint[$i]}$white" | tee -a $Logpath/verifier.txt;
  done | column -t
  printf "\n";

}

ValidateHealthCheck
ValidateInstDetails
ValidateGCLog
ValidateAppLog
ValidateCatalina
ValidateThreadDumps
if [[ jqOut != "NOTINSTALLED" ]] ; then
{
  ValidateDBRStats
  ValidatePerfLogStats
}
fi
PrintSuggestions
exit
