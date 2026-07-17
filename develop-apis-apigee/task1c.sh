#!/bin/bash -x

cd ~/develop-apis-apigee/rest-backend

source config.sh

export RESTHOST=$(gcloud run services describe simplebank-rest --platform managed --region $CLOUDRUN_REGION --format json | jq -r '.metadata.annotations."run.googleapis.com/urls" | fromjson[0]')
echo "export RESTHOST=${RESTHOST}" >> ~/.bashrc
curl -vH "Authorization: Bearer $(gcloud auth print-identity-token)" -X GET "${RESTHOST}/_status"

curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" -H "Content-Type: application/json" -X POST "${RESTHOST}/customers" -d '{"lastName": "Diallo", "firstName": "Temeka", "email": "temeka@example.com"}'

gcloud firestore import gs://spls/shared/firestore-simplebank-data/firestore/example-data

curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" -X GET "${RESTHOST}/atms"
curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" -X GET "${RESTHOST}/atms/spruce-goose"
