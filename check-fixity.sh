#!/bin/bash
# Checks fixity of a specific AIP using the Storage Service fixity check API
#
# Dependencies:
#
# 1. Requires curl and jq versions 1.4 or 1.5.


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
