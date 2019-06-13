#!/bin/bash

# Reads from user configuration file
# Meant to be sourced from other scripts

errorExit(){
	message=$1
	echo -e "$message" >&2
	echo "Exiting ..." >&2
	exit
}

# set some defaults
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

# read variables from config file

# archivematica variables
am_username=$(jq -r .am_username < "$user_config") 
am_api_key=$(jq -r .am_api_key < "$user_config")
am_host=$(jq -r .am_host < "$user_config")
transfer_source_uuid=$(jq -r .am_transfer_source_uuid < "$user_config")
transfer_source_root=$(jq -r .am_transfer_source_root < "$user_config") # Archivematica's path to transfer source

# storage service variables
ss_host=$(jq -r .ss_host < "$user_config")
ss_username=$(jq -r .ss_username < "$user_config")
ss_api_key=$(jq -r .ss_api_key < "$user_config")

# script location variables
log_dir=$(jq -r .log_dir < "$user_config") # script will put logs here
scripts_dir=$(jq -r .scripts_dir < "$user_config") # path where check-fixity.sh script can be found

# check if required directories and files exist
if [ ! -d "$transfer_source_root" ]
then
	errorExit "The transfer source path \"$transfer_source_root\" is not accessible. Please check the configuration."
fi

if [ ! -d "$scripts_dir" ]
then
	errorExit "The scripts directory could not be located. Please check the configuration."
fi

if [ ! -d "$log_dir" ]
then
    errorExit "The log directory $log_dir does not exist, please check the configuration."
fi