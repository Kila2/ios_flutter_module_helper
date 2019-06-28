#!/bin/sh
if [ -d ".ios" ] || [ -d ".android" ]
then 
  echo 'its a flutter project'
else
  echo "Not in flutter project"
  exit
fi
open -a Simulator
flutter run -d all
pod lib create --template-url=https://github.com/Kila2/ios_flutter_template.git $1
echo $1 > .FlutterModuleNameiOS
