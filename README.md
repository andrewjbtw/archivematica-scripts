# archivematica-scripts
Bash scripts for use with an Archivematica installation

# Overview

These scripts

- automate the ingest of AIPs into Archivematica
- check the fixity of a stored AIP
- check the fixity of all AIPs in archival storage

To run the scripts, you must have:

1. Access to an Archivematica installation
2. Access to the Archivematica Storage Service connected to that installation
3. Read/write access to the Archivematica "transfer source" location you will be using
4. Read/write access to a folder on the machine where you run the script that can be used to store the scripts' logs

# Ingest

#### single-ingest.sh

Start a new ingest, or reattach to one that is already in progress.

Usage:
```
single-ingest.sh -t <absolute/path/to/transfer> [ -w <wait time in seconds> ] [ -u <transfer uuid> ]
```

*-t transfer*

Required. Enter the absolute path to the folder to be ingested.

*-w wait time* (in seconds)

Optional. This is the frequency with which the script checks the status of the package in Archivematica. Defaults to five minutes.

*-u uuid*

Optional, but required to reattach to an existing transfer. To find the UUID of the existing transfer, either check the output of the script used to start the transfer, or find the transfer and its UUID listed on the Archivematica dashboard.

### How it works

#### New transfers

For a new transfer, the script

- sends a transfer to Archivematica (unzipped or zipped bags only)
- monitors the course of ingest by reporting back progress on the command line
- checks the fixity of the resulting AIP after it's been sent to archival storage
- reports back basic summary information about the ingested package
- moves the "original" folder in the transfer source to a "pending deletion" directory where it can be deleted after confirming that the ingest was successful

*Note*: You can run more than one transfer at the same time (by calling the script from different shells), but you can't run two transfers with the same name at the same time. This was done out of caution to prevent name collisions within Archivematica (which does not assign UUIDs until after a transfer starts), and to prevent accidentally sending the same folder or zip file twice.

The script uses a lock file to track the name of each running transfer (one lock file per transfer). The lock file is only deleted after the transfer is ingested as an AIP. If the transfer fails or is rejected, you will have to manually remove the lock file, which is stored in the log directory. This can help serve as a reminder to review any failures or rejections before attempting to ingest the same transfer(s) again.

#### Reattaching to an ingest in progress

If the script is interrrupted and an ingest is already in progress, you can "reattach" the script to that ingest. It will then complete everything listed above except for the initial (already completed) step of starting a transfer. To reattach, you will need

- the path to the original folder in the transfer source location
- the UUID assigned to that package at the "transfer" stage

The UUID is required to make sure that you are reattaching to the correct package. The path to the original folder is required so that it can be moved to the pending deletion directory after the AIP has been ingested.

Because the script runs a number of post-ingest tasks, it's best to reattach it if it gets interrupted for any reason. This will ensure that the fixity check runs automatically after the AIP reaches archival storage and that the lock file gets deleted if every step is completed successfully. If the script is not reattached, then it will be necessary to run those steps manually.

The important thing to keep in mind is that ultimately Archivematica controls the ingest after the transfer has been started. From that point until the AIP is stored, the script is just checking back for status updates and then acting on the information it receives. So if the script crashes or otherwise gets disconnected, but Archivematica remains online, the ingest will remain active in Archivematica itself. This is what makes it possible to reattach the script.

#### Screen output

The script logs a minimal amount of information to the screen. Here's the output for an example transfer (named "example"):

```
$ ./single-ingest.sh -t /transfer_source/example

----------------
11/Jun/2019:23:02:58 -0700      Starting transfer for: example, unzipped bag
11/Jun/2019:23:03:08 -0700      example copied successfully to Archivematica. Waiting for approval.
11/Jun/2019:23:03:18 -0700      example is ready for approval
11/Jun/2019:23:03:18 -0700      Approving example
11/Jun/2019:23:03:19 -0700      Status of example: Transfer, PROCESSING
11/Jun/2019:23:08:38 -0700      Status of example: Transfer, USER_INPUT
11/Jun/2019:23:13:58 -0700      Status of example: Transfer, USER_INPUT
11/Jun/2019:23:19:05 -0700      Status of example: Transfer, USER_INPUT
11/Jun/2019:23:24:19 -0700      Status of example: Transfer, COMPLETE
11/Jun/2019:23:24:20 -0700      Status of example: SIP, PROCESSING, Check for submission documentation
11/Jun/2019:23:29:37 -0700      Status of example: SIP, USER_INPUT, Store AIP
11/Jun/2019:23:34:51 -0700      Status of example: SIP, COMPLETE, Remove the processing directory
11/Jun/2019:23:34:51 -0700      SIP example completed with UUID: 8b5893f3-fcca-4ab7-b5f8-2acf0e546de5 and size: 444545394
11/Jun/2019:23:34:51 -0700      Moving /transfer_source/example to pending deletion folder.
11/Jun/2019:23:35:21 -0700      Checking fixity for AIP UUID: 8b5893f3-fcca-4ab7-b5f8-2acf0e546de5
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100   123    0   123    0     0     80      0 --:--:--  0:00:01 --:--:--    80
11/Jun/2019:23:35:23 -0700      Result of fixity check on 8b5893f3-fcca-4ab7-b5f8-2acf0e546de5: success

```

Tasks with the status of USER_INPUT require decisions to be made using the Archivematica dashboard. The script will wait indefinitely until a decision is made. If your processing configuration is set to make all choices automatically, then the script will run straight through until ingest is complete and the AIP passes a fixity check. This means that it is possible to fully automate ingest by setting the processing configuration to never ask for input.

#### Logs

This script logs two outputs to files that are stored in the log directory (which you can choose in the configuration file):

1. The results of the fixity check on the stored AIP. This is stored as a JSON line appended to a log file named "post-ingest-fixity-check.log". Note that more recent versions of Archivematica store the results of fixity checks in the Storage Service, so maintaining your own log is no longer strictly necessary, but this feature pre-dates that functionality.
2. A CSV line containing the following information: AIP Name, UUID, size. This line is stored in a CSV text file listing all completed ingests from the same day and can be found in a subdirectory of the log directory named "completed ingests".

#### File management

When a transfer has been ingested successfully, it is automatically moved to a subfolder in the pending deletion directory named for the date on which the ingest was completed. The folder path takes the following form:

<code>/transfer_source/ingested-pending-deletion/YYYY-MM-DD/</code>

The transfer folder is also renamed to include the AIP UUID assigned by Archivematica. This is to prevent name collisions if two transfers on the same day have the same name.

For the example above, the pending deletion directory path for the "example" folder is:

<code>/transfer_source/ingested-pending-deletion/2019-06-11/example-8b5893f3-fcca-4ab7-b5f8-2acf0e546de5</code>

It would be possible to change the code to delete transfers automatically after ingest, but out of caution they are simply moved to a folder where they could be reviewed and deleted later. I generally delete the previous day's transfers in a batch after confirming that they were ingested without error.

# Fixity checking

#### check-fixity.sh

Checks the fixity of an AIP in archival storage.

#### full-fixity-check.sh

Checks the fixity of all AIPs in archival storage.

# Installation

To install:

1. Install dependencies. Install **jq** and **curl** if they are not already installed on your system. They are required to work with the Archivematica APIs.
2. Clone this repository.
3. Create a directory named ".archivematica" in your user's home folder
4. Copy the configuration template file named "am-user-config.json.template" to your ".archivematica" folder.
5. Following the instructions in the configuration file, enter the required configuration values and rename the file to am-user-config.json

The complete configuration file should take the following form:

```JSON
{"am_username":"Archivematica username",
"am_api_key":"Archivmatica API_key",
"am_host":"URL or IP address of Archivematica server",
"am_transfer_source_uuid":"uuid of transfer source",
"am_transfer_source_root":"full path to transfer source, as recorded in the Storage Service",
"ss_host":"URL or IP address of Storage Service server",
"ss_username":"Storage Service username",
"ss_api_key":"Storage Service API key",
"log_dir":"directory to store logs, must be writable by user running the script",
"scripts_dir":"directory where the scripts from this repository are located"
}
```

6. Run one of the scripts to make sure it works. I recommend starting with a fixity check on a small AIP, as it's the simplest command. In the future, I'll add a script that simply requests information from Archivematica, which is probably the safest way to test your configuration.

# Dependencies

- jq - for working with JSON
- curl - for sending API requests

# Design goals

# Comparison with automation tools