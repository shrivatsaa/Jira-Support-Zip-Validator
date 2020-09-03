# Jira-Support-Zip-Validator
The idea behind the support Zip Validator is to provide a consolidated overview of all these relevant files and provide an assessment of any known errors or issues that we know from our experience. It can be run individually or along with a data file LogErrorDataFile.txt filled already with the list of errors that we usually associate with indexing and performance problems. It can also be modified to add more error messages to look for based on your troubleshooting experience. In case you want to skip the data file, fill in the same error messages in the script file itself. 

Run the script in one of the following ways:

The below would validate all the logs for the current date. But also look for known error messages that has happened in the past. 

./szvalidator.sh <Unzipped support folder path>

The below would look for all the error messages and other issues for the specific date that is provided and also report on any historical error messages including current date for root cause analysis.

./szvalidator.sh <Unzipped support folder path> <date in YYYY-MM-DD format>

As mentioned earlier add the known error messages followed by the suggestion or related KB in LogErrorDataFile.txt file for future use. Currently its pre-filled with some commonly known problems. Error message to be scanned are entered in the format of Error meessage|suggestion with error message and suggestion separated by a pipe. Ex.

Indexing failed for Issue|Indexing errors seen for issues. Refer https://confluence.atlassian.com/jirakb/troubleshoot-a-reindex-failure-in-jira-server-429917142.html
