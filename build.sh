#!/bin/bash

# helps keeping the control file up to date according to:
# http://sourceforge.net/p/fhem/code/HEAD/tree/trunk/fhem/docs/LIESMICH.update-thirdparty

# print a list of UPD commands for the package to stdout
find ./FHEM/ -type f|sort|xargs ls -l --time-style +%Y-%m-%d_%H:%M:%S| awk '{print "UPD", $6, $5, substr($7, 3)}'

