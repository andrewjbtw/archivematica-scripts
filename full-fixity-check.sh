#!/bin/bash

user_config="$HOME"/.archivematica/am-user-config.json # required configuration file

# check for user config file
if [ ! -f "$user_config" ]
then
    errorExit "No configuration file found at $user_config"
else
    if [ "$(jq 'any(. == "")' < "$user_config")" == "true" ]
    then
        errorExit "One or more configuration values are empty. Please check the configuration file and start over."
        fi
fi

# storage service variables
ss_host=$(jq -r .ss_host < "$user_config")
ss_username=$(jq -r .ss_username < "$user_config")
ss_api_key=$(jq -r .ss_api_key < "$user_config")

# script location variables
log_dir=$(jq -r .log_dir < "$user_config") # script will put logs here
scripts_dir=$(jq -r .scripts_dir < "$user_config") # path where check-fixity.sh script can be found

# needed for logging
start_date=$(date -I) # fixity checks could take days, but start date won't change
next="api/v2/file/" 
uuids=""
results_dir=$log_dir/full-fixity-checks/"$start_date"

# create directory to log fixity check results
mkdir -pv "$results_dir"

# Build the list of UUIDs. Exclude non-ingested UUIDs (deletion, failed ingests).
echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tGathering list of UUIDs"

while [ "$next" != "null" ] ; do 
    resultset=$(curl -s -X GET -H"Authorization: ApiKey $ss_username:$ss_api_key" http://"$ss_host/$next" | jq .)
    next=$(echo "$resultset" | jq .meta.next | tr -d '"')
    uuids=$uuids$(echo "$resultset" | jq --raw-output '.objects[] | select(.package_type == "AIP") | select(.status == "UPLOADED") |  .uuid')$'\n'
done

# Create an intermediate file to list UUIDs to be checked

echo -en "$uuids" > $results_dir/uuids-"$start_date".txt

if [ ! -f "$results_dir"/"verification-$start_date".log ] 
then
    touch "$results_dir"/"verification-$start_date".log # create log file
fi

# Check fixity on all packages in the UUID list
# TODO Log to JSON to make analysis easier
 
while read aip_uuid
do
    if (grep -q "$aip_uuid" "$results_dir"/"verification-$start_date".log)
    then
        echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tFixity has already been checked for $aip_uuid"
    else
        sleep 2 # Storage service was reporting errors when checking still images in rapid succession
        fixity_result=$($scripts_dir/check-fixity.sh "$aip_uuid")
        if [ "$(echo $fixity_result | jq .result.success)" != "true" ]
        then
            echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tWARNING: Fixity check failed on $aip_uuid. See fixity-error.log for details."
            echo "Press enter to continue." # pause on fixity error; may be sign of connection or server problem
            read placeholder
        else
            echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tResult of fixity check on $aip_uuid: success"
            echo "$fixity_result" >> "$results_dir"/"verification-$start_date".log
        fi
    fi

done < "$results_dir"/uuids-"$start_date".txt