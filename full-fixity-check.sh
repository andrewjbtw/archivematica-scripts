#!/bin/bash

if [ -f ./read-config.sh ]
then
    source ./read-config.sh
else
    echo "Can't read configuration file. Check if the path to read-config.sh is correct."
fi

usage() {
cat >&2 << END_USAGE
Usage: full-fixity-check.sh [ -r <start date of check to resume> ]

If run with no options, starts a new fixity check on all AIPs in storage.

-r      Resume a full fixity check that was cancelled or interrupted. 
        Supply the start date for that check in the form YYYY-MM-DD
END_USAGE
exit 1
}

lockfile="$log_dir"/running-fixity-check.lock
if [ -f "$lockfile" ]
then
    echo "Lock file found. A fixity check may be running."
    exit
else
    touch "$log_dir"/running-fixity-check.lock
fi

cleanUp(){
    if [ -f "$lockfile" ]
    then
        echo -e "\nCleaning up lock file."
        rm -v "$lockfile"
    fi
}

trap cleanUp EXIT

# Fixity checks could take days, but start date won't change
# Defaults to current date but can be overridden when using the '-r' option to resume
start_date=$(date -I)

# Read input options
while [ "$1" != "" ]
do
    case "$1" in
        -r )    shift
                start_date=$1 # For resuming, need to supply original start date
                if [ -z "$start_date" ] # Make sure date isn't empty
                then
                    echo -e "Please supply the starting date for the check you are resuming.\n"
                    usage
                else
                    if [ ! -d "$log_dir"/full-fixity-checks/"$start_date" ] # Make sure directory exists
                    then
                        echo "No fixity check found starting on $start_date. Please check the date and try again."
                        exit 1
                    fi
                fi
                ;;
        * )     echo -e "Unknown option \"$1\" found!\n"
                usage
                ;;
    esac
    shift
done

# Directory to log results of the fixity check
results_dir="$log_dir"/full-fixity-checks/"$start_date"
mkdir -pv "$results_dir"


# Variables needed for gathering the list of uuids
next="/api/v2/file/" # The Storage Service API uses this value to cycle through paginated results
uuids=""

# Build the list of UUIDs. Exclude non-ingested UUIDs (deletions, failed ingests).
echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tGathering list of UUIDs"

while [ "$next" != "null" ] ; do 
    resultset=$(curl -s -X GET -H"Authorization: ApiKey $ss_username:$ss_api_key" http://"${ss_host}${next}" | jq .)
    next=$(echo "$resultset" | jq .meta.next | tr -d '"')
    uuids=$uuids$(echo "$resultset" | jq --raw-output '.objects[] | select(.package_type == "AIP") | select(.status == "UPLOADED") |  .uuid')$'\n'
done

# Create an intermediate file to list all uuids in storage
# If resuming, this will add any uuids stored since the fixity check started
echo -en "$uuids" > "$results_dir"/uuids-"$start_date".txt

if [ ! -f "$results_dir"/verification-"$start_date".log ] 
then
    touch "$results_dir"/verification-"$start_date".log # create log file
fi

# Check fixity on all packages in the UUID list
 
while read aip_uuid
do
    if (grep -q "$aip_uuid" "$results_dir"/"verification-$start_date".log)
    then
        echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tFixity has already been checked for $aip_uuid"
    else
        sleep 2 # Storage service was reporting errors when checking in rapid succession
        fixity_result=$($scripts_dir/check-fixity.sh "$aip_uuid")
        if [ "$(echo $fixity_result | jq .result.success)" != "true" ]
        then
            echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tWARNING: Fixity check failed on $aip_uuid. See the error logs for details."
            echo "Logging uuid to error log."
            echo -e "$aip_uuid" >> "$results_dir"/uuids-failed-"$start_date".log
            echo "Press enter to continue." # Pause on fixity error; may be sign of connection or server problem
            read placeholder
        else
            echo -e "$(date '+%d/%b/%Y:%H:%M:%S %z')\tResult of fixity check on $aip_uuid: success"
            echo "$fixity_result" >> "$results_dir"/"verification-$start_date".log
        fi
    fi
done < "$results_dir"/uuids-"$start_date".txt

rm "$lockfile"