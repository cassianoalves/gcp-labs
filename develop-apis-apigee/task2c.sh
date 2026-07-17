#!/bin/bash -x

cd ~/develop-apis-apigee/rest-backend
source config.sh

PROJECT_NUMBER=$(gcloud projects describe $GOOGLE_CLOUD_PROJECT --format="value(projectNumber)")
# A conta de serviço do lab que você está usando para o proxy
SERVICE_ACCOUNT="apigee-internal-access@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com"

export INSTANCE_NAME=eval-instance
export ENV_NAME=eval
if [ -z "${GOOGLE_CLOUD_PROJECT}" ]
then
  echo "Error: GOOGLE_CLOUD_PROJECT environment variable is not set. Please set it to your project ID."
else
  export PREV_INSTANCE_STATE=
  echo "waiting for runtime instance ${INSTANCE_NAME} to be active"
  while :
  do
    export INSTANCE_STATE=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" -X GET "https://apigee.googleapis.com/v1/organizations/${GOOGLE_CLOUD_PROJECT}/instances/${INSTANCE_NAME}" | jq "select(.state != null) | .state" --raw-output)
    [[ "${INSTANCE_STATE}" == "${PREV_INSTANCE_STATE}" ]] || (echo
    echo "INSTANCE_STATE=${INSTANCE_STATE}")
    export PREV_INSTANCE_STATE=${INSTANCE_STATE}
    [[ "${INSTANCE_STATE}" != "ACTIVE" ]] || break
    echo -n "."
    sleep 5
  done
  echo
  echo "instance created, waiting for environment ${ENV_NAME} to be attached to instance"
  while :
  do
    export ATTACHMENT_DONE=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" -X GET "https://apigee.googleapis.com/v1/organizations/${GOOGLE_CLOUD_PROJECT}/instances/${INSTANCE_NAME}/attachments" | jq "select(.attachments != null) | .attachments[] | select(.environment == \"${ENV_NAME}\" or (.environment | endswith(\"/${ENV_NAME}\"))) | .environment" --raw-output)
    [[ -n "${ATTACHMENT_DONE}" ]] && break
    echo -n "."
    sleep 5
  done
  echo
  echo "${ENV_NAME} environment attached"
  echo "***ORG IS READY TO USE***"
fi


echo "Concedendo a role 'iam.serviceAccountTokenCreator' para o Agente Apigee..."
gcloud iam service-accounts add-iam-policy-binding $SERVICE_ACCOUNT \
  --role="roles/iam.serviceAccountTokenCreator" \
  --member="serviceAccount:service-$PROJECT_NUMBER@gcp-sa-apigee.iam.gserviceaccount.com"

