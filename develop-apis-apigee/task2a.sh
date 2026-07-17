#!/bin/bash -x

cd ~/develop-apis-apigee/rest-backend
source config.sh

gcloud iam service-accounts create apigee-internal-access \
--display-name="Service account for internal access by Apigee proxies" \
--project=${GOOGLE_CLOUD_PROJECT}

gcloud run services add-iam-policy-binding simplebank-rest \
--member="serviceAccount:apigee-internal-access@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com" \
--role=roles/run.invoker --region=$CLOUDRUN_REGION \
--platform=managed \
--project=${GOOGLE_CLOUD_PROJECT}

gcloud projects add-iam-policy-binding ${GOOGLE_CLOUD_PROJECT} \
--member="serviceAccount:apigee-internal-access@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator"


gcloud run services describe simplebank-rest --platform managed \
  --region $CLOUDRUN_REGION \
  --format json | jq -r '.metadata.annotations."run.googleapis.com/urls" | fromjson[0]'

