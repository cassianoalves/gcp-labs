#!/bin/bash

gcloud services enable translate.googleapis.com --project=$GOOGLE_CLOUD_PROJECT

gcloud iam service-accounts create apigee-proxy \
    --display-name="apigee-proxy"

gcloud projects add-iam-policy-binding ID_DO_SEU_PROJETO \
    --member="serviceAccount:apigee-proxy@ID_DO_SEU_PROJETO.iam.gserviceaccount.com" \
    --role="roles/logging.logWriter"



# Configurações - Substitua com os seus dados
PROJECT_ID=$GOOGLE_CLOUD_PROJECT
ENVIRONMENT="eval"
PROXY_NAME="translate-v1"

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
  -H "Authorization: Bearer ${TOKEN}"

echo -e "\n\n=== Limpando arquivos temporários ==="
rm -rf ${PROXY_NAME} ${PROXY_NAME}.zip

echo "Processo concluído!"