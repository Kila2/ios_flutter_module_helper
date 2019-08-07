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
  echo 'ios_deploy ready'
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
cd ios
pod install
cd $SRCROOT
#BUG XCode11无法打armv7
xcodebuild clean build -workspace $SRCROOT/ios/Runner.xcworkspace -scheme Runner -configuration Debug -sdk iphonesimulator -arch x86_64 CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO EXPANDED_CODE_SIGN_IDENTITY=- EXPANDED_CODE_SIGN_IDENTITY_NAME=- CONFIGURATION_BUILD_DIR=$SRCROOT/build/miniapp/iphonesimulator && \
xcodebuild clean build -workspace $SRCROOT/ios/Runner.xcworkspace -scheme Runner -configuration Release -sdk iphoneos -arch arm64 -arch armv7 CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO EXPANDED_CODE_SIGN_IDENTITY=- EXPANDED_CODE_SIGN_IDENTITY_NAME=- FLUTTER_BUILD_MODE=release CONFIGURATION_BUILD_DIR=$SRCROOT/build/miniapp/iphoneos
echo 'run reslove_dependency.rb'
ruby $SRCROOT/reslove_dependency.rb $SRCROOT
echo 'run reslove_dependency.rb finish'
exit 0
