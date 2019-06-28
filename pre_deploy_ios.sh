#!/bin/sh
SRCROOT=`pwd`
PODNAME=`cat $SRCROOT/.FlutterModuleNameiOS`
if [ -d ".ios" ] || [ -d ".android" ]
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
xcodebuild clean build -workspace $SRCROOT/${PODNAME}/Example/${PODNAME}.xcworkspace -scheme ${PODNAME}-Example -configuration Debug -sdk #iphonesimulator -arch x86_64 CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO EXPANDED_CODE_SIGN_IDENTITY=- #EXPANDED_CODE_SIGN_IDENTITY_NAME=- CONFIGURATION_BUILD_DIR=$SRCROOT/build/miniapp/iphonesimulator && \
xcodebuild clean build -workspace $SRCROOT/${PODNAME}/Example/${PODNAME}.xcworkspace -scheme ${PODNAME}-Example -configuration Release -sdk #iphoneos -arch arm64 CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO EXPANDED_CODE_SIGN_IDENTITY=- #EXPANDED_CODE_SIGN_IDENTITY_NAME=- FLUTTER_BUILD_MODE=release CONFIGURATION_BUILD_DIR=$SRCROOT/build/miniapp/iphoneos
cd $SRCROOT/.ios/Flutter/engine && \
zip -r $SRCROOT/Flutter.zip Flutter.framework && \
cd $SRCROOT/build && \
cp -r $SRCROOT/build/miniapp/iphonesimulator/${PODNAME}_Example.app/Frameworks/App.framework $SRCROOT/build/
cp -r $SRCROOT/build/miniapp/iphoneos/${PODNAME}_Example.app/Frameworks/App.framework $SRCROOT/build/App-device.framework
lipo -create $SRCROOT/build/App.framework/App $SRCROOT/build/App-device.framework/App -output $SRCROOT/build/App.framework/App
zip -rm $SRCROOT/Flutter.zip App.framework && \
rm -rf $SRCROOT/build/App.framework
rm -rf $SRCROOT/build/App-sim.framework
#添加三方库和插件
ALLFRAMEWOEK=\'App.framework\',\'Flutter.framework\'
cd $SRCROOT/build
for file in $SRCROOT/build/miniapp/iphoneos/*.framework
do 
  if [[ $file = *Pods_${PODNAME}_Example.framework ]]; then
    continue
  fi
  nameext=${file##*/}
  ALLFRAMEWOEK=${ALLFRAMEWOEK},\'${nameext}\'
  echo ${ALLFRAMEWOEK}
  name=${nameext%.*}
  cp -r $SRCROOT/build/miniapp/iphoneos/${name}.framework $SRCROOT/build/
  cp -r $SRCROOT/build/miniapp/iphonesimulator/${name}.framework $SRCROOT/build/${name}-sim.framework
  lipo -create $SRCROOT/build/${name}.framework/${name} $SRCROOT/build/${name}-sim.framework/${name} -output $SRCROOT/build/${name}.framework/${name}
  zip -rm $SRCROOT/Flutter.zip ${name}.framework && \
  rm -rf $SRCROOT/build/${name}.framework
  rm -rf $SRCROOT/build/${name}-sim.framework
done
cd $SRCROOT/ios_deploy
# git pull && \
mv $SRCROOT/Flutter.zip $SRCROOT/ios_deploy && \
# git add Flutter.zip && \
cd $SRCROOT
if [ -f "${SRCROOT}/ios_deploy/${PODNAME}.podspec" ] 
then
 echo "nothing" >> /dev/null
else
 cp ${SRCROOT}/${PODNAME}/${PODNAME}FlutterModule.podspec ${SRCROOT}/ios_deploy/${PODNAME}.podspec
fi
#for linux
#sed -i "s/s.vendored_frameworks.*/s.vendored_frameworks = ${ALLFRAMEWOEK}/" ${SRCROOT}/ios_deploy/${PODNAME}.podspec
#for mac
#sed -i n.tmp "s/s.vendored_frameworks.*/s.vendored_frameworks = ${ALLFRAMEWOEK}/" ${SRCROOT}/ios_deploy/${PODNAME}.podspec
sed -i n.tmp "s/s.vendored_frameworks.*/s.vendored_frameworks = ${ALLFRAMEWOEK}/" ${SRCROOT}/ios_deploy/${PODNAME}.podspec
