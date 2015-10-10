#!/bin/bash

#############
# Variables #
#############

SAVEIFS=$IFS
IFS=$(echo -en "\n\b")

# Significant locations
# Original report location
folder1="/opt/rapid7/nexpose/nsc/reports/gs__reporting"

# Processed JSON formatted report location
folder2="/opt/jsondata/reports/json"

# Copied CSV formatted report location
# to prevent issues with original data
folder3="/opt/jsondata/reports/nexpose"

# Processed directory where
# we move the original reports to
# so that they are not processed again
folder4="/opt/rapid7/nexpose/nsc/reports/gs__reporting/processed"

# Report Type directories
# (you can add your own types with some code modification)
folder5="/opt/jsondata/reports/json/scan"
folder6="/opt/jsondata/reports/json/exception"
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
for f in ${folder1}/SQL-*/${oreport}
        do
        if [ -e "$f" ]
        then
                echo "Unprocessed reports exist."
                mcp "${folder1}/*/${oreport}" "${folder3}/#1.${ext1}"
                logger -i [Nexpose Report Processor] Processing Nexpose reports for gs__reporting
                break
        else
                echo "There are no reports to process."
                logger -i [Nexpose Report Processor] There were no reports to #process
                exit 1
fi
done

####################################
# Process all files in new nexpose #
# reporting directory to json      #
# format and move to json reporting#
# directory using csvkit's csvjson #
####################################

for report in ${folder3}/*.$ext1
do
        echo "$report is the full path/filename being formatted for json"
        # filename
        filename=$(basename "$report")
        # Extension
        extension="${filename##*.}"
        # basename
        fileroot="${filename%.*}"
        # Determine if json format of files already exist
        if ! [ -e "${folder2}/${fileroot}.${ext2}" ]
        then
                csvjson $report > ${folder2}/$fileroot.$ext2
        fi
        ## Move the reports to their respective directories
        type=$(echo $filename | egrep -o 'Exception' | head -n1)
        if [ "$type" == "Exception" ]
        then
                mv ${folder2}/${fileroot}.${ext2} ${folder6}/${fileroot}.${ext2}
                rm -f ${folder3}/${fileroot}.${ext1}
        else
                mv ${folder2}/${fileroot}.${ext2} ${folder5}/${fileroot}.${ext2}
                rm -f ${folder3}/${fileroot}.${ext1}
        fi

done
IFS=$SAVEIFS

function prep {
        repo=($folder5/*.$ext2 $folder6/*.$ext2)
        for file in ${repo[@]}
        do
                # Remove enclosing brackets
                sed -i 's/\(\[\|\]\)//g' $file
                # Add a new line after closing brace and comma
                sed -i 's/\}\,/}\n/g' $file
                # Replace all spaces between two words with underscores
                sed -i -e 's/\(\w\)\s\(\w\)/\1_\2/g' $file
		# Truncate all floating points
		sed -i -e 's/\([0-9]\{1,4\}\).\([0-9]\)\([0-9]\)\([0-9]\{2,16\}\)/\1.\2/g' $file
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
mv ${folder1}/SQL* ${folder4}

