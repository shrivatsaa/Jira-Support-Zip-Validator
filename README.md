# Jira-Support-Zip-Validator
The idea behind the support Zip Validator is to provide a consolidated overview of all these relevant files and provide an assessment of any known errors or issues that we know from our experience. The script scans through different log files in the support zip and makes insights out of it without the need to manually parse them. This is an accessory to other UI and non-UI based tools that you are currently utilizing to parse logs, parse thread dumps, plot graphs independently, by providing a consolidated overview and inferring suggestions and insights out of the various log files. This tool is essentially meant to provide a good enough first shot to take to solving problems, followed by which you can utilize the existing tools for detailed analysis.

First things first, the script is run with a general format as below
./szvalidator.sh -p <Product(optional)> <folderName> <Date(optional)>

The date and the product, qualified by the option -p are optional. They default to the current date when date is not given, while the support zip folder name with any spaces removed is necessary. The option -p will be explained later down the line. In its simplest form it can be run as before
./szvalidator.sh <foldername> <Date(optional)>

The script parses and provides analysis of the following folders and files in the support zip.

Healthcheck.txt - Highlights the healthchecks that failed and need review

atlassian-jira.log - It might require a little more detail and context on how this log is parsed,since it differs a bit from the earlier version of the script. Similar to hercules that scans the log files for well known errors and makes suggestions, the script uses a data file ‘LogErrorData.txt’ to look for list of errors and make corresponding suggestions. Rather than use an exhaustive list, which consumes a lot of time to parse, its left to us end users, to define well known and critical errors you look for in a product and corresponding suggestions, which could be a KB link or product guide.

The list of error messages would be defined under a header of the format <product>_Log_Messages and footer ProductSeparator. A lookup table is defined inside the script to identify what messages to scan for in the application log, based on the value provided for option -p in the above script. The valid values for -p are 'JSW', 'Perf', 'JSM', 'Insight', 'Roadmaps'.

So the following would scan the log for Jira Software related error messages that you define in the LogErrorData.txt file under the header JSW_Log_Messages and footer ProductSeparator

./szvalidatorNew.sh -p JSW supportzip_folder_2023-05-23

The following would scan only for performance related problems in the application log for performance related error messages that you define in the LogErrorData.txt file under the header Performance_Log_Messages and footer ProductSeparator

./szvalidatorNew.sh -p perf supportzip_folder_2023-05-23

GC logs - Will scan for full GC occurrences in both openjdk and oracle JDK format files for the current date. It will also additionally scan for any GC incidents in the past 6 days.
![image](https://github.com/user-attachments/assets/330b127b-8dbd-4ec9-b2d9-16dfbe38f99f)

catalina.out - Scan for heap dump file names and out of memory errors, information on stuck threads from struckthreaddetectionvalve, thread dumps if generated will be parsed and dumped in the folder where script is run from.
![image](https://github.com/user-attachments/assets/ada7daf7-6fad-4b5c-a43e-61b157941d5a)

Thread dump analysis - A thread dump overview with user and url details will be provided from the last five threads generated from the JFR, when enabled, for 9.x versions. Otherwise the support tool generated thread dumps will be parsed and analyzed. The number of thread dumps parsed is limited to 4 for readability in a shell window. The thread dump analysis also provides information on top requests and users and additionally lists down the object monitor locks and threads waiting on these monitor locks.
<img width="1738" alt="Thread_Dump_Analysis" src="https://github.com/user-attachments/assets/44a8f9c6-019b-48c5-9c24-36b247ebdfb1" />


DBR related statistics - DBR(Document based replication) stats are parsed and any long breach of the threshold for these statistics are noted and corresponding warning for on IO and network latency are raised.
![image](https://github.com/user-attachments/assets/4e06a092-0413-45f7-904c-f114c8eaf35e)

atlassian-perf.log - Some of the jmx metrics dumped in these logs are parsed for any concerning trends such as high load averages, thread counts etc.
![image](https://github.com/user-attachments/assets/d54f0874-e217-4e1e-9c4d-d634c5f67ade)

Finally a suggestion list is generated with a category of critical, Major and minor suggestions along with errors found from application log messages. This will provide an overview of what needs to be immediately addressed and reviewed.
![image](https://github.com/user-attachments/assets/9ba9962f-38ce-4817-ab64-dce857c03dcf)


