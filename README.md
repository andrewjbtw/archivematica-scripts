# archivematica-scripts
Bash scripts for use with an Archivematica installation

# Overview

These scripts are designed to automate the ingest of AIPs into Archivematica and to check the fixity of stored packages.

To run the scripts, you must have:

1. Access to an Archivematica installation
2. Access to the Archivematica Storage Service connected to that installation
3. Read/write access to the Archivematica "transfer source" location you will be using
4. Read/write access to folders on the machine running the script that can be used for storing logs

# Ingest

#### single-ingest.sh

For a new transfer, this script

- sends a transfer to Archivematica (unzipped or zipped bags only)
- monitors the course of ingest by reporting back progress on the command line
- checks the fixity of the resulting AIP after it's been sent to archival storage
- reports back basic summary information about the ingested package
- moves the "original" folder in the transfer source to a new directory where it can be deleted after confirming that the ingest was successful

If the script is interrrupted and an ingest is already in progress, the script can "reattach" to the ingest. It will then complete everything listed above except for the initial step of starting a transfer. To reattach, you will need

- the path to the original folder in the transfer source location
- the UUID assigned to that package at the "transfer" stage

The UUID is required to make sure that you are reattaching to the correct package. The path to the original folder is required so that it can be moved after the AIP has been ingested. 

The important thing to keep in mind is that ultimately Archivematica controls the ingest after it starts. The script is just checking back for status updates and then acting on the information it receives. So if the script crashes or gets disconnected, but Archivematica remains online, the ingest will remain active in Archivematica itself.

Usage:
```
single-ingest.sh -t <absolute/path/to/transfer> [ -w <wait time in seconds> ] [ -u <transfer uuid> ]
```

*-t transfer*

Required. Enter the absolute path to the folder to be ingested from the transfer source.

*-w wait time* (in seconds)

Optional. This is the frequency with which the script checks the status of the package in Archivematica. Defaults to five minutes.

*-u uuid* 

Optional, but required to reattach to an existing transfer. To find the UUID of the existing transfer, either check the output of the script used to start the transfer, or find the transfer and its UUID listed on the Archivematica dashboard.

Outputs:

This script logs two outputs to files in the log directory:

1. The results of the fixity check on the stored AIP. This is stored as a JSON line appended to a log file named "post-ingest-fixity-check.log". Note that more recent versions of Archivematica store the results of fixity checks in the Storage Service, so maintaining your own log is no longer strictly necessary.
2. A CSV line containing the following information: AIP Name, UUID, size. This line is stored in a CSV text file listing all completed ingests from the same day and can be found in a subdirectory of the log directory named "completed ingests".

# Fixity checking

#### check-fixity.sh

Checks the fixity of an AIP in archival storage.

#### full-fixity-check.sh

Checks the fixity of all AIPs in archival storage.

# Installation

# Dependencies

# Design goals

# Comparison with automation tools