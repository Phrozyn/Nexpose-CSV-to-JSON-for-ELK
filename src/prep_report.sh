#!/bin/bash

#############
# Variables #
#############

SAVEIFS=$IFS
IFS=$(echo -en "\n\b")

# Significant locations
# Original report location
nx_report_dir="/opt/rapid7/nexpose/nsc/reports/gs__reporting"

# Processed JSON formatted report location
json_working_dir="/opt/jsondata/reports/json"

# Copied CSV formatted report location
# to prevent issues with original data
nx_working_dir="/opt/jsondata/reports/nexpose"

# Processed directory where
# we move the original reports to
# so that they are not processed again
json_processed_dir="/opt/rapid7/nexpose/nsc/reports/gs__reporting/processed"

# Report Type directories
# (you can add your own types with some code modification)
json_scan_dir="/opt/jsondata/reports/json/scan"
json_exception_dir="/opt/jsondata/reports/json/exception"
# Filename Extensions we are working with
ext1="csv"
ext2="json"
# Original report name
oreport="report.csv"

###################################
# Rename all reports to           #
# foldername_report.csv using mcp #
# and move them to new            #
# unprocessed reporting directory #
###################################
for f in ${nx_report_dir}/SQL-*/${oreport}
        do
        if [ -e "$f" ]
        then
                echo "Unprocessed reports exist."
                mcp "${nx_report_dir}/*/${oreport}" "${nx_working_dir}/#1.${ext1}"
                logger -i [Nexpose Scan Report Processor] Processing Nexpose reports for gs__reporting
                break
        else
                echo "There are no reports to process."
                logger -i [Nexpose Scan Report Processor] There were no reports to #process
                exit 1
fi
done


####################################
# Process all files in new nexpose #
# reporting directory to json      #
# format and move to json reporting#
# directory using csvkit's csvjson #
####################################

for report in ${nx_working_dir}/*.$ext1
do
        echo "$report is the full path/filename being formatted for json"
        # filename
        filename=$(basename "$report")
        # Extension
        extension="${filename##*.}"
        # basename
        fileroot="${filename%.*}"
        # Determine if json format of files already exist
        if ! [ -e "${json_working_dir}/${fileroot}.${ext2}" ]
        then
                csvjson $report > ${json_working_dir}/$fileroot.$ext2
        fi
        ## Move the reports to their respective directories
        type=$(echo $filename | egrep -o 'Exception' | head -n1)
        if [ "$type" == "Exception" ]
        then
                mv ${json_working_dir}/${fileroot}.${ext2} ${json_exception_dir}/${fileroot}.${ext2}
        else
                mv ${json_working_dir}/${fileroot}.${ext2} ${json_scan_dir}/${fileroot}.${ext2}
        fi

done
IFS=$SAVEIFS

function prep {
        repo=($json_scan_dir/*.$ext2 $json_exception_dir/*.$ext2)
        for file in ${repo[@]}
        do
                # Remove enclosing brackets
                sed -i 's/\(\[\|\]\)//g' $file
                # Add a new line after closing brace and remove comma
                sed -i 's/\}\,/}\n/g' $file
                # Replace all spaces between two words with underscores
                sed -i -e 's/\(\w\)\s\(\w\)/\1_\2/g' $file
                # Replace space after a colon with Underscore
                sed -i -e 's/\(\w\):\s\(\w\)/\1:_\2/g' $file
                # Replace space before a parentheses with underscore
                sed -i -e 's/\(\w\)\s\W\(\w\)/\1_\(\2/g' $file
                # Truncate all floating points
                sed -i -e 's/\.\([0-9]\)\([0-9]\)\{3,16\}/\.\1/g' $file
                # Modify Date Time entry (Scan date and Submitted date only)
                sed -i -e 's/-\([0-9]\{2\}\)_\([0-9]\{2\}\)/-\1T\2/g' $file
                # Add a new line at the end of the file
                sed -i -e '$a\' $file
                # # Add index according to type
                if [[ $file =~ .*Exception.* ]]
                then
                        sed -i 's/{/{"index":{"_index":"nexpose","_type":"exception"}}\n{/g' $file
                        # Bulk post json events into elk
                        curl --user kibbles:meddlingKid5 'http://elk.phrozyn.net:909/_bulk?' --data-binary @$file
                else
                        sed -i 's/{/{"index":{"_index":"nexpose","_type":"scan"}}\n{/g' $file
                        # Bulk post json events into elk
                        curl --user kibbles:meddlingKid5 'http://elk.phrozyn.net:909/_bulk?' --data-binary @$file
                fi

        done
}
prep
# Move processed reports to processed directory
mv ${nx_report_dir}/SQL* ${json_processed_dir}
