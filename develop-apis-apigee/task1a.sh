#!/bin/bash

if [ $# -lt 1 ]
then
  echo "Use $0 <region>"
  exit 1
fi

set -x

ln -s ~/training-data-analyst/quests/develop-apis-apigee ~/develop-apis-apigee
cd ~/develop-apis-apigee/rest-backend
export CLOUDRUN_REGION=$1
sed -i "s/us-west1/$CLOUDRUN_REGION/g" config.sh
source config.sh
./init-project.sh

#git clone --depth 1 https://github.com/cassianoalves/training-data-analyst.git

#git clone --depth 1 https://github.com/GoogleCloudPlatform/training-data-analyst

set +x