#!/bin/bash

# Generates list of all AIPs recorded in the Archivematica Storage Service
# Note that deleted AIPs and AIPs that failed the "Store AIP" microservice are also listed
# TODO update this to filter AIPs by status as an option (i.e. list only stored AIPs)

source ./read-config.sh # checks current directory for script to read config file

usage(){
cat >&2 << END_USAGE
usage: get-aip-info.sh -u <uuid> | -a

Options are mutually exclusive: 

-u <uuid> retrieves information for the AIP with that UUID
-a retrieves information for all AIPs and stores it in a JSON file in the log directory
END_USAGE
}

if [ "$#" -eq 0 ]
then
    usage
fi

# process options

while [ "$1" != "" ]
do
	case "$1" in
		-u )  shift
		      uuid=$1
              ;;
		-a )  shift
		      get_all=true # override default if -w was supplied as option
		      ;;
		* )   echo "Unknown option '$1' found!" >&2
              usage
              ;;
	esac
	shift
done

if [ "$get_all" == "true" ]
then
	retrieval_time=$(date +"%F-%H-%M-%S")
	next="/api/v2/file/"

	while [ "$next" != "null" ] ; do
	    resultset=$(curl -s -X GET -H"Authorization: ApiKey $ss_username:$ss_api_key" "${ss_host}${next}" | jq .)
	    next=$(echo "$resultset" | jq .meta.next | tr -d '"')
	    alljson=$alljson$(echo "$resultset" | jq --raw-output . )$'\n'
	done
	echo -en "$alljson" > "$log_dir"/all-aips-"$retrieval_time".json
else
	api_response=$(curl -s -X GET -H"Authorization: ApiKey $ss_username:$ss_api_key" "$ss_host/api/v2/file/$uuid/")
	if [ -z "$api_response" ]
	then
		echo "The uuid $uuid did not return any results from the Storage Service. Please check if you have the correct uuid."
	else
		echo "$api_response" | jq .
	fi
fi
