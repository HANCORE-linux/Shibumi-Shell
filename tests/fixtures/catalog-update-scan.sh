#!/bin/sh
# Inert update scanner for the catalog-interest separation test. No network.
/usr/bin/sleep 1
printf '%s\n' PLUGIN_UPDATE_COUNT=0 PLUGIN_CHECKED_COUNT=1 PLUGIN_UNMANAGED_COUNT=0 PLUGIN_FETCH_FAILED_COUNT=0
