#!/bin/bash

gcloud services enable translate.googleapis.com --project=$GOOGLE_CLOUD_PROJECT

gcloud iam service-accounts create apigee-proxy \
    --display-name="apigee-proxy"

gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
    --member="serviceAccount:apigee-proxy@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com" \
    --role="roles/logging.logWriter"



# Configurações - Substitua com os seus dados
PROJECT_ID=$GOOGLE_CLOUD_PROJECT
ENVIRONMENT="eval"
PROXY_NAME="translate-v1"
SERVICE_ACCOUNT=apigee-proxy@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com
PROJECT_NUMBER=$(gcloud projects describe $GOOGLE_CLOUD_PROJECT --format="value(projectNumber)")


echo "=== 1. Criando estrutura de diretórios do proxy ==="
mkdir -p ${PROXY_NAME}/apiproxy/proxies
mkdir -p ${PROXY_NAME}/apiproxy/targets

echo "=== 2. Criando o arquivo de configuração principal (${PROXY_NAME}.xml) ==="
cat <<EOF > ${PROXY_NAME}/apiproxy/${PROXY_NAME}.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<APIProxy revision="1" name="${PROXY_NAME}">
    <Basepaths>/translate/v1</Basepaths>
    <ConfigurationVersion majorVersion="4" minorVersion="0"/>
    <DisplayName>${PROXY_NAME}</DisplayName>
    <Profiles/>
    <ProxyEndpoints>
        <ProxyEndpoint>default</ProxyEndpoint>
    </ProxyEndpoints>
    <TargetEndpoints>
        <TargetEndpoint>default</TargetEndpoint>
    </TargetEndpoints>
</APIProxy>
EOF

echo "=== 3. Criando o ProxyEndpoint (default.xml) ==="
cat <<EOF > ${PROXY_NAME}/apiproxy/proxies/default.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<ProxyEndpoint name="default">
    <Description/>
    <FaultRules/>
    <PreFlow name="PreFlow">
        <Request/>
        <Response/>
    </PreFlow>
    <PostFlow name="PostFlow">
        <Request/>
        <Response/>
    </PostFlow>
    <Flows/>
    <HTTPProxyConnection>
        <BasePath>/translate/v1</BasePath>
        <Properties/>
    </HTTPProxyConnection>
    <RouteRule name="default">
        <TargetEndpoint>default</TargetEndpoint>
    </RouteRule>
</ProxyEndpoint>
EOF

echo "=== 4. Criando o TargetEndpoint com autenticação GoogleAccessToken ==="
cat <<EOF > ${PROXY_NAME}/apiproxy/targets/default.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<TargetEndpoint name="default">
    <Description/>
    <FaultRules/>
    <PreFlow name="PreFlow">
        <Request/>
        <Response/>
    </PreFlow>
    <PostFlow name="PostFlow">
        <Request/>
        <Response/>
    </PostFlow>
    <Flows/>
    <HTTPTargetConnection>
        <URL>https://translation.googleapis.com/language/translate/v2</URL>
        <Authentication>
            <GoogleAccessToken>
                <Scopes>
                    <Scope>https://www.googleapis.com/auth/cloud-translation</Scope>
                </Scopes>
            </GoogleAccessToken>
        </Authentication>
    </HTTPTargetConnection>
</TargetEndpoint>
EOF

echo "=== 5. Compactando o pacote do proxy ==="
cd ${PROXY_NAME}
zip -r ../${PROXY_NAME}.zip apiproxy
cd ..

echo "=== 6. Obtendo token de autenticação do Gcloud ==="
TOKEN=$(gcloud auth print-access-token)

echo "=== 7. Enviando o proxy para o Apigee (Import) ==="
curl -X POST "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/apis?name=${PROXY_NAME}&action=import" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@${PROXY_NAME}.zip"

echo -e "\n\n=== 8. Fazendo o Deploy no ambiente: ${ENVIRONMENT} ==="
curl -X POST "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/environments/${ENVIRONMENT}/apis/${PROXY_NAME}/revisions/1/deployments" \
  -H "Content-Type: application/json" \
  -d "{\"serviceAccount\": \"$SERVICE_ACCOUNT\"}" \
  -H "Authorization: Bearer ${TOKEN}"

echo -e "\n\n=== Limpando arquivos temporários ==="
rm -rf ${PROXY_NAME} ${PROXY_NAME}.zip


export INSTANCE_NAME=eval-instance
export ENV_NAME=eval
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
  export ATTACHMENT_DONE=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" -X GET "https://apigee.googleapis.com/v1/organizations/${GOOGLE_CLOUD_PROJECT}/instances/${INSTANCE_NAME}/attachments" | jq "select(.attachments != null) | .attachments[] | select(.environment == \"${ENV_NAME}\") | .environment" --join-output)
  [[ "${ATTACHMENT_DONE}" != "${ENV_NAME}" ]] || break
  echo -n "."
  sleep 5
done
echo "***ORG IS READY TO USE***"


echo "Concedendo a role 'iam.serviceAccountTokenCreator' para o Agente Apigee..."
gcloud iam service-accounts add-iam-policy-binding $SERVICE_ACCOUNT \
  --role="roles/iam.serviceAccountTokenCreator" \
  --member="serviceAccount:service-$PROJECT_NUMBER@gcp-sa-apigee.iam.gserviceaccount.com"

echo "Processo concluído!"


curl -i -k -X POST "https://eval.example.com/translate/v1" -H "Content-Type: application/json" -d '{ "q": "Translate this text!", "target": "es" }'

