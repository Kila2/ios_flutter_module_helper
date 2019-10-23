#!/bin/sh
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
SRCROOT=`pwd`
if [ -d "ios" ] || [ -d "android" ]
then
  echo 'its a flutter project'
else
  echo "Not in flutter project"
  exit
fi
if [ -d "ios_deploy" ]
then
  rm -rf ios_deploy
  mkdir ios_deploy
else
  mkdir ios_deploy
fi && \
if [ -f "$SRCROOT/ios_deploy/Flutter.zip" ]
then
  rm $SRCROOT/ios_deploy/Flutter.zip  
else
 echo 'output dir is clean'  
fi && \
if [ -f "$SRCROOT/ios/Podfile.lock" ]
then
  rm $SRCROOT/ios/Podfile.lock
else
  echo 'no podfile.lock'  
fi 
if [ -d "$SRCROOT/.ios" ]
then
  rm -rf $SRCROOT/.ios
else
  echo 'no .ios'  
fi 
flutter packages get
echo 'run reslove_dependency.rb'
ruby $SRCROOT/reslove_dependency.rb $SRCROOT
echo 'run reslove_dependency.rb finish'
exit 0
