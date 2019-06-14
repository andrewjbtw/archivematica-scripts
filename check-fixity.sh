#!/bin/bash
# Checks fixity of a specific AIP using the Storage Service fixity check API

if [ -f ./read-config.sh ]
then
    source ./read-config.sh
else
    echo "Can't read configuration file. Check if the path to read-config.sh is correct."
fi

if [ $# -ne 1 ]
then
    echo "Enter UUID:"
    read UUID
else
    UUID="$1"
fi

echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tChecking fixity for AIP UUID: $UUID" >&2

api_response=$(curl -X GET -H"Authorization: ApiKey $ss_username:$ss_api_key" "$ss_host/api/v2/file/$UUID/check_fixity/")

result=$(echo "$api_response" | jq -c --arg date_checked "$(date)" --arg UUID "$UUID" '. | {"UUID" : $UUID , "date checked": $date_checked, result: .}') 
success=$(echo "$result" | jq .result.success)
# echo "$result" >> /home/allusers/logs/check-fixity-new.log

if [ "$success" != "true" ] 
then
    echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tWARNING: Fixity check failed on $UUID. See fixity-error.log for details." | tee -a /home/allusers/logs/fixity-error.log >&2
    echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tStorage Service API response: $api_response" >> /home/allusers/logs/fixity-error.log
else
   echo "$result" 
fi 
