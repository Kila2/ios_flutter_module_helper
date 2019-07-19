#!/bin/sh
if [ -d "ios" ] || [ -d "android" ]
then 
  echo 'its a flutter project'
else
  echo "Not in flutter project"
  exit
fi

echo $1 > .APFShotiOS
