#!/bin/sh
echo "last_build = \"`date '+%Y-%m-%d %H:%M:%S %Z'`\"" > lastBuild.txt
REVISION_INFO=$((`git rev-list HEAD --count`+10))  #  +10 to match old SVN rev
#  REVISION_INFO=`(cd ..; svn status -v . --depth=empty | awk '{print $1}')`
echo "svn_revision = $REVISION_INFO" >> lastBuild.txt
