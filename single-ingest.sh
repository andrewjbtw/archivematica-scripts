#!/bin/bash

#set -x

usage(){
cat >&2 << END_USAGE
usage: single-ingest.sh -t <absolute/path/to/transfer> [ -w <wait time in seconds> ] [ -u <transfer uuid> ]

With only the -t option, starts a new Archivematica transfer.

To reattach to a running transfer, combine -t and -u and supply both the path
to the transfer in the transfer source and the transfer uuid assigned by Archivematica.
END_USAGE
exit
}

errorExit(){
	message=$1
	echo -e "$message" >&2
	echo "Exiting ..." >&2
	exit 1
}

if [ "$#" -eq 0 ]
then
    usage
fi

if [ -f ./read-config.sh ]
then
    source ./read-config.sh
else
    echo "Can't read configuration file. Check if the path to read-config.sh is correct."
fi

# set some defaults
wait_time=300 # time between progress checks during ingest. Defaults to 5 minutes, can override with -w option.

# process options

while [ "$1" != "" ]
do
	case "$1" in
		-t )  shift
		      transfer=$1
              ;;
		-w )  shift
		      wait_time=$1 # override default if -w was supplied as option
		      ;;
		-u )  shift
		      transfer_uuid=$1
		      reattach=true
		      ;;
		* )   echo -e "Unknown option '$1' found! Quitting ...\n" >&2
              usage
              ;;
	esac
	shift
done

# check if required directories and files exist
if [ ! -d "$transfer_source_root" ]
then
	errorExit "The transfer source path \"$transfer_source_root\" is not accessible. Please check the configuration."
fi

if [ ! -f "$scripts_dir/check-fixity.sh" ]
then
	errorExit "The fixity checking script could not be located. Please check the configuration."
fi

if [ ! -d "$log_dir" ]
then
    errorExit "The log directory $log_dir does not exist, please check the configuration."
else
    mkdir -pv "$log_dir/completed-ingests" # create log folder for completed ingests if it doesn't already exist
fi

# check if path to transfer exists
if [ ! -d "$transfer" ] && [ ! -f "$transfer" ]
then
    errorExit "\n----------------\nWarning: $transfer not found"
fi

# Get the name and ID of the transfer to refer to later
# At the start, the transfer name is the name of the folder or zip file to be ingested
# However, the .zip extension will be dropped during ingest, so the persistent identifier (transfer ID) for the .zip is the name without the extension
# For zipped bags, both the transfer name and transfer ID are needed to start the transfer and then track it
transfer_name=$(basename "$transfer")
transfer_id=${transfer_name/.zip/}

# Begin the "start transfer" block
# The if-then section sends a transfer to Archivematica and then approves it
# The else section skips "start transfer" and validates the transfer name and uuid to reattach to an existing transfer
if [ ! "$reattach" == "true" ]
then
    transfer_source_root_escaped=$(echo "$transfer_source_root" | sed 's/\//\\\//g') # be careful with the path separators
    relative_source_path=$(echo "$transfer" | sed -e "s/^$transfer_source_root_escaped\///g") # archivematica API asks for path relative to transfer source location

    # make sure the path to the transfer is actually located below the transfer source root path
    if [ "$transfer_source_root/$relative_source_path" != "$transfer" ]
    then
        errorExit "The selected transfer cannot be found in the transfer source directory."
    fi

    # Check if transfer is already being processed
    # Stop if lock file found, create lock file if this is a new transfer
    if [ ! -f "$log_dir"/"$transfer_id".lock ]
    then
        touch "$log_dir"/"$transfer_id".lock
    else
        errorExit "\n----------------\nID $transfer_id is already in process"
    fi

    # If transfer is a file, check if it is a zip
    if [ -f "$transfer" ]
    then
        if (echo "$transfer" | grep -q "\.zip$") && (file "$transfer" | grep -q "Zip archive")
        then
            transfer_type="zipped bag"
        else
            errorExit "\n----------------\nError: $transfer is not a valid zip"
            exit
        fi
    fi

    # If transfer is a directory, check if it is a bag
    if [ -d "$transfer" ]
    then
        if [ -f "$transfer/bagit.txt" ]
        then
            transfer_type="unzipped bag"
        else
            errorExit "\n----------------\nError: no bagit.txt found in $transfer"
            exit
        fi
    fi

    # Encode location and path in base64, as required by the Archivematica API
    source_base64=$(echo -n "$transfer_source_uuid:$relative_source_path" | base64 -w 0)

    # Copy transfer to Archivematica
    echo -e "\n----------------\n$(date '+%d/%b/%Y:%H:%M:%S %z')\tStarting transfer for: $transfer_name, $transfer_type"
    start_result=$(curl -s --data "username=$am_username&api_key=$am_api_key" --data "name=$transfer_name&type=$transfer_type" --data "paths[]=[$source_base64]" "http://$am_host/api/transfer/start_transfer/")

    if [ "$(echo "$start_result" | jq --raw-output .message)" = "Copy successful." ]
    then
        echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\t$transfer_name copied successfully to Archivematica. Waiting for approval."
        sleep 10
    else
        echo "Something went wrong." # TODO: catch this error more formally
        echo "$start_result" | jq .
        exit
    fi

    # Approve transfer
    # Need to wait until copied folder becomes available for approval.
    while true
    do
        check_unapproved=$(curl -s "http://$am_host/api/transfer/unapproved?username=$am_username&api_key=$am_api_key")
        if ( echo "$check_unapproved" | jq .results[].directory | grep -q "$transfer_name" )
        then
            echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\t$transfer_name is ready for approval"
            break
        else
            echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tStill waiting for $transfer_name to be ready for approval"
            sleep 30
        fi
    done

    echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tApproving $transfer_name"
    approve_result=$(curl -s --data "username=$am_username&api_key=$am_api_key&type=$transfer_type&directory=$transfer_name" "http://$am_host/api/transfer/approve")
    transfer_uuid="$(echo "$approve_result" | jq --raw-output .uuid)"

    # If the transfer is a zipped bag, Archivematica will drop the zip extension after approval, so track it by name without the .zip
    if [ "$transfer_type" == "zipped bag" ]
    then
         transfer_name=$transfer_id
    fi
else
    # check that the transfer ID and uuid supplied on the command line actually match
    retrieve_transfer_by_uuid=$(curl -s "http://$am_host/api/transfer/status/$transfer_uuid?username=$am_username&api_key=$am_api_key")
    check_transfer_name=$(echo "$retrieve_transfer_by_uuid" | jq -r .name)
    if [ "$transfer_id" != "$check_transfer_name" ]
    then
        echo "$transfer_id"
        echo "$check_transfer_name"
        errorExit "The name $transfer_name does not match the uuid $transfer_uuid"
    fi
fi # end block for starting a new transfer

while true 
do
    if [ "$transfer_status" == "COMPLETE" ]
    then
        sip_uuid="$(echo "$transfer_status_full" | jq --raw-output .sip_uuid)"
        sip_status_full=$(curl -s "http://$am_host/api/ingest/status/$sip_uuid?username=$am_username&api_key=$am_api_key" | jq .)
        sip_status="$(echo "$sip_status_full" | jq --raw-output .status)"
        sip_microservice="$(echo "$sip_status_full" | jq --raw-output .microservice)"
        sip_name="$(echo "$sip_status_full" | jq --raw-output .name)"
        echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tStatus of $sip_name: SIP, $sip_status, $sip_microservice"

        if [ "$sip_status" == "COMPLETE" ] # Finish processing and write to logs
        then
            # get AIP size
            aip_size=$(curl -s -X GET -H"Authorization: ApiKey $ss_username:$ss_api_key" "$ss_host/api/v2/file/$sip_uuid/" | jq .size)
            echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tSIP $sip_name completed with UUID: $sip_uuid and size: $aip_size"
            echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tMoving $transfer to pending deletion folder."
            pending_deletion_dir="/$transfer_source_root/ingested-pending-deletion/$(date -I)"
            mkdir -p "$pending_deletion_dir"
            # mv "$transfer" "$pending_deletion_dir"/"$(basename "$transfer")"-$(date +"%F-%H-%M-%S")
            mv "$transfer" "$pending_deletion_dir"/"$(basename "$transfer")-$sip_uuid"

            # check fixity of stored package
            sleep 30 # wait for storage service to be updated post-ingest
            fixity_result=$("$scripts_dir"/check-fixity.sh "$sip_uuid")
            if [ "$(echo "$fixity_result" | jq .result.success)" != "true" ]
            then
                echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tWARNING: Fixity check failed on $UUID. See fixity-error.log for details."
                echo "Press CTRL+C to quit."
		sleep inf # pause on fixity error so that the user sees the issue. Do not exit here.
            else
                echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tResult of fixity check on $sip_uuid: success"
                echo "$fixity_result" >> "$log_dir"/post-ingest-fixity-check.log
            	echo "$sip_name,$sip_uuid,$aip_size" >> "$log_dir"/completed-ingests/completed-ingests-"$(date -I)".txt
		rm "$log_dir"/"$transfer_id".lock # remove lockfile
	    fi
	    exit
        fi
    else
        transfer_status_full=$(curl -s "http://$am_host/api/transfer/status/$transfer_uuid?username=$am_username&api_key=$am_api_key" | jq .)
        transfer_status="$(echo "$transfer_status_full" | jq --raw-output .status)"
	echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tStatus of $transfer_name: Transfer, $transfer_status"

        if [ "$transfer_status" == "COMPLETE" ]
        then
            continue # if SIP is complete, jump to next loop and check SIP status
        fi
    fi
    sleep "$(shuf -i "$wait_time"-$((wait_time+20)) -n1)" # random wait to avoid conflicts if more than one package is in process at the same time
done 
