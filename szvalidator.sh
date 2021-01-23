#!/bin/sh

usage="Run the script in the format ./szvalidator.sh <folder name of unzipped support.zip folder>";

FolderPath=$1;
Logpath=$FolderPath;
HealthcheckFile=$FolderPath/healthchecks/healthcheckResults.txt
ApplicationLogPath=$FolderPath/application-logs/
CatalinalogPath=$FolderPath/tomcat-logs/
GcLogPath1=$FolderPath/application-logs/
GcLogPath2=$FolderPath/tomcat-logs/
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

#List of messages to look for in the application log and corresponding suggestion. This array will be used if LogErrorData.txt file is lost or not available
messages=(
"java.lang.StackOverflowError|Look out for stuck threads and application stalling. Refer https://confluence.atlassian.com/jirakb/jira-applications-stall-due-to-stackoverflowerror-exception-941601100.html"
"Indexing failed for Issue|Indexing errors seen for issues. Refer https://confluence.atlassian.com/jirakb/troubleshoot-a-reindex-failure-in-jira-server-429917142.html"
"Indexing failed for ISSUE|Indexing errors seen for issues. But this could be owing to issue versioning and rest calls made to deleted issues not yet cleaned up from issue_version table. Verify the logs"
"Wait attempt timed out - waited|Look out for indexing and snapshot restore failures. Also look for nodereindexing threads or clustermessagehandler threads timing out waiting for index lock"
"Detected frequent flushes|Look out indexing related slowness. Refer https://confluence.atlassian.com/jirakb/jira-indexing-performance-and-lucene-maxrambuffermb-963659203.html"
"Bigpipe taking longer than 5s|Look out for cpu usage and other performance issues."
"There was an error getting a DBCP datasource|Verify any connection errors, stuck threads, full GCs or system resource overrun. Refer https://confluence.atlassian.com/adminjiraserver073/surviving-connection-closures-861253055.html"
)

if [ $# -eq 0 ] ; then
	echo "$usage";
	exit 1;
fi 

if [[ -f $Logpath/verifier.txt ]] ; then
	{
		rm $Logpath/verifier.txt > /dev/null;
	} 
fi

if [[ "$OSTYPE" = "linux-gnu"* ]]; then 
  sedvar='-e'
elif [[ "$OSTYPE" = "darwin"* ]]; then
  sedvar=''
else
  sedvar='-e'
fi

#Get the count of defined error message and make the suggestion
if [[ $2 != "" ]] ; then {
  checkdate=$2
} 
else {
  checkdate=$(date +"%Y-%m-%d")
}
fi

#Remove any empty lines from LogErrorData so that grep is not wasted for empty text searches
removeemptylines()
{
  if [[ -f LogErrorData.txt ]] ; then {
    sed -i "$sedvar" '/^$/d' LogErrorData.txt > /dev/null
  }
  fi
}

#Validate the health check results
ValidateHealthCheck()
{
  printf $combo'List of healtcheck failures : \n'$white | tee -a $Logpath/verifier.txt;	
  if [[ -f $HealthcheckFile ]] ; then {
    grep -h -A1 -B1 "Is healthy: false" $HealthcheckFile | grep -v "\-\-" |grep -v "Is healthy" |  awk 'NR%2!=0{key1=$0;getline;key2=$0;print key1" ---> "key2}' | tee -a $Logpath/verifier.txt;
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
    
    printf $combo'\nFull GC details :\n'$white | tee -a $Logpath/verifier.txt;
    if [[ $GCFilePath != "" ]] ; then {
      #Check for Full GCs in the GC files.	
      GCcount1=$(grep -c "$checkdate.*Full GC" $GCFilePath/*gc* | awk -F: '$2>0{sum+=$2}END{print sum}');
      if [[ $GCcount1 -gt 0 ]] ; then {
        echo $green"$GCcount1 instances of $white $red Full GCs $white $green found on $checkdate.$white $blue It can be ignored if its from system.gc or metadata GC threshold\n"$white | tee -a $Logpath/verifier.txt;
       }
      fi
      
      GCcount2=$(grep -c "Full GC" $GCFilePath/*gc* | awk -F: '$2>0{sum+=$2}END{print sum}');
      if [[ $GCcount2 -gt 0 ]] ; then {
        GCcount=$((GCcount2 - GCcount1))
        echo $green"$GCcount Instances of Full GC found but not on today or given date.$white $blue Verify the logs for historical full GCs.\n"$white | tee -a $Logpath/verifier.txt;	
      }
      fi
       
      if [[ $GCcount1 -eq 0 && $GCcount2 -eq 0 ]] ; then {
         echo $green"No Full GCs were found in the provided GC logs.\n"$white | tee -a $Logpath/verifier.txt;
      }
      fi

    }  
else {
	echo $cyan'No GC files of type atlassian-jira-gc found either in tomcat-logs or application-logs. Skipping GC checks\n'$white | tee -a $Logpath/verifier.txt;
    }
    fi
}

#Validate the Application log for errors.
ValidateAppLog()
{
  printf $combo'Application log contains following errors : \n'$white | tee -a $Logpath/verifier.txt;	
  if [[ -f $ApplicationLogPath/atlassian-jira.log ]] ; then {

    if [[ -f LogErrorData.txt ]] ; then {

      #Check for errors of different types found in the the LogErrorData.txt file
      while read -r line
      do
         #Get the error message
         error=$(echo $line | awk -F"|" '{print $1}');
         #Get the suggestion message
         Suggestion=$(echo $line | awk -F"|" '{print $2}');

         #Get the number of occurrences of different errors based on date
         count=$(grep -c "$checkdate.*$error" $ApplicationLogPath/atlassian-jira.log* | awk -F: '$2>0{sum+=$2}END{print sum}');
         if [[ $count -gt 0 ]] ; then {
         echo $green"$count instances of errors of type$white $red $error $white $green found on $checkdate.$white $blue $Suggestion\n"$white | tee -a $Logpath/verifier.txt;
         ErrorAvail=1;
         }
         #check again without the date filter and report the errors seen
         else {
           count=$(grep -c "$error" $ApplicationLogPath/atlassian-jira.log* | awk -F: '$2>0{sum+=$2}END{print sum}');
           if [[ $count -gt 0 ]] ; then {
           echo $green"Errors of type$white $red $error $white $green found but not on today or given date.$white $blue $Suggestion\n"$white | tee -a $Logpath/verifier.txt;	
           ErrorAvail=1;
           }
           fi
         }  
         fi
      done < LogErrorData.txt
      if [[ $ErrorAvail -eq 0 ]] ; then {
         echo $green"Found no errors based on the list of errors in the messages variable in the script or LogErrorData.txt. Verify application logs for other errors or update script with more data for future.\n"$white | tee -a $Logpath/verifier.txt;
      }
      fi
    }
    else 
    {
      for ((i=0;i<${#messages[*]};i++));
      do
	     #Get the error message
         error=$(echo ${messages[$i]} | awk -F"|" '{print $1}');
         #Get the suggestion message
         Suggestion=$(echo ${messages[$i]} | awk -F"|" '{print $2}');

         #Get the number of occurrences of different errors based on date
         count=$(grep -c "$checkdate.*$error" $ApplicationLogPath/atlassian-jira.log* | awk -F: '$2>0{sum+=$2}END{print sum}');
         if [[ $count -gt 0 ]] ; then {
         echo $green"$count instances of errors of type$white $red $error $white $green found on $checkdate.$white $blue $Suggestion\n"$white | tee -a $Logpath/verifier.txt;
         ErrorAvail=1;
         }
         #check again without the date filter and report the errors seen
         else {
           count=$(grep -c "$error" $ApplicationLogPath/atlassian-jira.log* | awk -F: '$2>0{sum+=$2}END{print sum}');
           if [[ $count -gt 0 ]] ; then {
           echo $green"Errors of type$white $red $error $white $green found but not on today or given date.$white $blue $Suggestion\n"$white | tee -a $Logpath/verifier.txt;
           ErrorAvail=1;	
           }
           fi
         }  
         fi
      done    
      if [[ $ErrorAvail -eq 0 ]] ; then {
         echo $green"Found no errors based on the list of errors in the messages variable in the script or LogErrorData.txt. Verify application logs for other errors or update script with more data for future.\n"$white | tee -a $Logpath/verifier.txt;
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
  if [[ -f $CatalinalogPath/catalina.out ]] ; then {

  maxsize=200000000;
  CatalinaFileSize=$(stat -f%z "$CatalinalogPath/catalina.out")

  #Check if the file size is greater than 100MB then avoid parsing it
  if (( $CatalinaFileSize > $maxsize )); then {
    echo $cyan'Catalina.out file size is greater than 200MB. Skipping catalina.out checks. Please split the files to smaller ones or change the maxsize variable value in script and re-run it\n'$white | tee -a $Logpath/verifier.txt;
  }
  else 
	{
      HeapSpaceCount=$(grep -c "java.lang.OutOfMemoryError: Java heap space" $CatalinalogPath/catalina.out);
      if [[ $HeapSpaceCount -gt 0 ]] ; then {           
          echo $green"Errors of type $red java.lang.OutOfMemoryError: Java heap space $white $green were found. $white $blue Please verify if its valid for the current date\n"$white | tee -a $Logpath/verifier.txt;  
          ErrorAvail=1;
      }
      fi
      OutOfMemoryErrorCount=$(grep -c "Dumping heap to" $CatalinalogPath/catalina.out);
      if [[ $OutOfMemoryErrorCount -gt 0 ]] ; then {
      	  echo $green"We see $red Heap dumps have been generated. $white $blue Please verify if its valid for the current date from catalina.out.\n"$white | tee -a $Logpath/verifier.txt;
      	  ErrorAvail=1;
      }   
      fi 
      TDumpCount=$(grep -c "JNI global references" $CatalinalogPath/catalina.out);
      if [[ $TDumpCount -gt 0 ]] ; then {
      	  echo $green"Threads dumps seem to have been generated. Parsing thread dumps from catalina.out now and placing it in current directory. $white $blue Please verify if its valid for the current date\n"$white | tee -a $Logpath/verifier.txt;
          awk '/^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$/{n++;td=1;lastLine=$0;outFile=("thread_dump_" n ".txt")}; {if (td) {print $0 >> outFile; close(outFile)}}; /JNI global references/{if (lastLine ~ /garbage-first/ || lastLine ~ /Metaspace/) {td=0}}' $CatalinalogPath/catalina.out
          ErrorAvail=1;
      } 
      fi
      Finddate=$(date +%d-%b-%Y)
      StuckThreadCount=$(grep $Finddate.*org.apache.catalina.valves.StuckThreadDetectionValve.notifyStuckThreadDetected $CatalinalogPath/catalina.out | awk '{print $(NF-13)}' | sed -e 's/\[//g' -e 's/\]//g' | awk '{if ($0>max) max=$0}END{print max}');
      if [[ $StuckThreadCount -gt 10 ]] ; then {
          echo $green"Found $red $StuckThreadCount stuck threads $white $green at some point of time today as per StuckThreadDetectionValve. $white $blue Please verify if its valid for the current date from catalina.out\n"$white | tee -a $Logpath/verifier.txt;
          ErrorAvail=1;
      }
      fi
      if [[ $ErrorAvail -eq 0 ]] ; then {
          echo $green"Found no heap dump or our of memory or stuck threads and thread dumps in catalina.out. Verify individually for further issues.\n"$white | tee -a $Logpath/verifier.txt;
      }
      fi
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
  echo "\n$bold Number of Processors $normal : $NumOfProcs" | tee -a $Logpath/verifier.txt;

  TotalPhysMem=$(grep -o "<total-physical-memory>.*</total-physical-memory>" $FolderPath/application-properties/application.xml | sed -e "s/<total-physical-memory>//g" -e "s/<\/total-physical-memory>//g" | tr ' ' '\n');
  echo "\n$bold Total Physical Memory $normal : $TotalPhysMem" | tee -a $Logpath/verifier.txt;

  NumOfIssues=$(grep -o "<Issues>.*</Issues>" $FolderPath/application-properties/application.xml | sed -e "s/<Issues>//g" -e "s/<\/Issues>//g" | tr ' ' '\n');
  echo "\n$bold Number of Issues $normal : $NumOfIssues" | tee -a $Logpath/verifier.txt; 
   
  MaxFileDesc=$(grep -o "<max-file-descriptor>.*</max-file-descriptor>" $FolderPath/application-properties/application.xml | sed -e "s/<max-file-descriptor>//g" -e "s/<\/max-file-descriptor>//g" | tr ' ' '\n');
  echo "\n$bold Max File Descriptor $normal : $MaxFileDesc" | tee -a $Logpath/verifier.txt; 

  DBType=$(grep -o "<Database-type>.*</Database-type>" $FolderPath/application-properties/application.xml | sed -e "s/<Database-type>//g" -e "s/<\/Database-type>//g" | tr ' ' '\n');
  echo "\n$bold Database Type $normal : $DBType" | tee -a $Logpath/verifier.txt; 

  NumOfCustFields=$(grep -o "<Custom-Fields>.*</Custom-Fields>" $FolderPath/application-properties/application.xml | sed -e "s/<Custom-Fields>//g" -e "s/<\/Custom-Fields>//g" | tr ' ' '\n');
  echo "\n$bold Number of Custom Fields $normal : $NumOfCustFields" | tee -a $Logpath/verifier.txt; 

  NumOfGroups=$(grep -o "<Groups>.*</Groups>" $FolderPath/application-properties/application.xml | sed -e "s/<Groups>//g" -e "s/<\/Groups>//g" | tr ' ' '\n');
  echo "\n$bold Number of Groups $normal : $NumOfGroups" | tee -a $Logpath/verifier.txt; 

  NumOfUsers=$(grep -o "<Users>.*</Users>" $FolderPath/application-properties/application.xml | sed -e "s/<Users>//g" -e "s/<\/Users>//g" | tr ' ' '\n');
  echo "\n$bold Number of Users $normal : $NumOfUsers" | tee -a $Logpath/verifier.txt; 

  JVMMemory=$(grep -o "<Total-Memory>.*</Total-Memory>" $FolderPath/application-properties/application.xml | sed -e "s/<Total-Memory>//g" -e "s/<\/Total-Memory>//g" | tr ' ' '\n');
  echo "\n$bold Total JVM Memory $normal : $JVMMemory" | tee -a $Logpath/verifier.txt; 

  JVMArgs=$(grep -o "<JVM-Input-Arguments>.*</JVM-Input-Arguments>" $FolderPath/application-properties/application.xml | sed -e "s/<JVM-Input-Arguments>//g" -e "s/<\/JVM-Input-Arguments>//g" | tr ' ' '\n');
  echo "\n$bold JVM Attributes $normal : $JVMArgs" | tee -a $Logpath/verifier.txt; 

  }
else
	{
	  echo $green'No application.xml found under application-properties folder. Skipping instance checks\n'$white | tee -a $Logpath/verifier.txt; 	
	}
    fi
}


removeemptylines
ValidateHealthCheck
ValidateGCLog
ValidateAppLog
ValidateCatalina
ValidateInstDetails
exit
