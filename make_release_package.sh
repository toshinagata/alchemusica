#!/bin/sh
# dt=`date +'%y%m%d'`
(cd build/Deployment; zip -r Alchemusica_latest.zip Alchemusica.app -x \*.DS_Store)
# (cd ..; zip -r Alchemusica_src_$dt.zip Alchemusica -x \*.svn/\* -x _\* -x \*/_\* -x \*.DS_Store -x Alchemusica/build\* -x Alchemusica/\*.zip)
# mv ../Alchemusica_src_$dt.zip ./
mv build/Deployment/Alchemusica_latest.zip ./
