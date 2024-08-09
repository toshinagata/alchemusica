#!/bin/sh
if [ -e .git ]; then
  REVISION_INFO=`git rev-list HEAD --count`
else
  REVISION_INFO=`awk '/svn_revision/ {print $3}' lastBuild.txt`
fi
if [ "$REVISION_INFO" = "" ]; then
  REVISION_INFO=0
fi
echo "last_build = \"`date '+%Y-%m-%d %H:%M:%S %Z'`\"" > lastBuild.txt
echo "svn_revision = $REVISION_INFO" >> lastBuild.txt
