#!/bin/bash

#curl -i -k -X POST "https://eval.example.com/translate/v1" -H "Content-Type: application/json" -d '{ "q": "Translate this text!", "target": "es" }'
#GET https://translation.googleapis.com/v3/projects/PROJECT_NUMBER_OR_ID/locations/global/supportedLanguages
#curl -i "https://translation.googleapis.com/v3/projects/$GOOGLE_CLOUD_PROJECT/locations/global/supportedLanguages" -H "Authorization: Bearer ${TOKEN}"
#
## Tests
#curl -i -k -X GET "https://eval.example.com/translate/v1/languages"
#curl -i -k -X POST "https://eval.example.com/translate/v1?lang=de" -H "Content-Type:application/json" -d '{ "text": "Hello world!" }'
#curl -i -k -X POST "https://eval.example.com/translate/v1" -H "Content-Type:application/json" -d '{ "text": "Hello world!" }'

# Configurações - Substitua com os seus dados
PROJECT_ID=$GOOGLE_CLOUD_PROJECT
ENVIRONMENT="eval"
PROXY_NAME="translate-v1"
SERVICE_ACCOUNT=apigee-proxy@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com
PROJECT_NUMBER=$(gcloud projects describe $GOOGLE_CLOUD_PROJECT --format="value(projectNumber)")


echo "=== 1. Criando estrutura completa de diretórios do proxy ==="
rm -rf ${PROXY_NAME} ${PROXY_NAME}.zip
mkdir -p ${PROXY_NAME}/apiproxy/proxies
mkdir -p ${PROXY_NAME}/apiproxy/targets
mkdir -p ${PROXY_NAME}/apiproxy/policies
mkdir -p ${PROXY_NAME}/apiproxy/resources/properties
mkdir -p ${PROXY_NAME}/apiproxy/resources/jsc

echo "=== 2. Criando o Property Set (language.properties) ==="
cat <<EOF > ${PROXY_NAME}/apiproxy/resources/properties/language.properties
output=es
caller=en
EOF

echo "=== 3. Criando a política AM-BuildTranslateRequest ==="
cat <<EOF > ${PROXY_NAME}/apiproxy/policies/AM-BuildTranslateRequest.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<AssignMessage continueOnError="false" enabled="true" name="AM-BuildTranslateRequest">
    <AssignVariable>
        <Name>text</Name>
        <Template>{jsonPath("$.text",request.content)}</Template>
    </AssignVariable>
    <AssignVariable>
        <Name>language</Name>
        <Template>{firstnonnull(request.queryparam.lang,propertyset.language.output)}</Template>
    </AssignVariable>
    <Set>
        <Payload contentType="application/json">{"q": "{text}", "target": "{language}"}</Payload>
    </Set>
    <AssignTo createNew="false" transport="http" type="request"/>
</AssignMessage>
EOF

echo "=== 4. Criando a política AM-BuildTranslateResponse ==="
cat <<EOF > ${PROXY_NAME}/apiproxy/policies/AM-BuildTranslateResponse.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<AssignMessage continueOnError="false" enabled="true" name="AM-BuildTranslateResponse">
    <AssignVariable>
        <Name>translated</Name>
        <Template>{jsonPath('$.data.translations[0].translatedText',response.content)}</Template>
    </AssignVariable>
    <Set>
        <Payload contentType="application/json">{"translated": "{translated}"}</Payload>
    </Set>
    <AssignTo createNew="true" transport="http" type="response"/>
</AssignMessage>
EOF

echo "=== 5. Criando a política AM-BuildLanguagesRequest ==="
cat <<EOF > ${PROXY_NAME}/apiproxy/policies/AM-BuildLanguagesRequest.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<AssignMessage continueOnError="false" enabled="true" name="AM-BuildLanguagesRequest">
    <AssignVariable>
        <Name>targetLanguage</Name>
        <Set>
            <Value ref="propertyset.language.caller"/>
        </Set>
    </AssignVariable>
    <Set>
        <Verb>POST</Verb>
        <Payload contentType="application/json">{"target": "{targetLanguage}"}</Payload>
    </Set>
    <AssignTo createNew="true" transport="http" type="request"/>
</AssignMessage>
EOF

echo "=== 6. Criando o código JavaScript e a política JS-BuildLanguagesResponse ==="
cat <<EOF > ${PROXY_NAME}/apiproxy/resources/jsc/JS-BuildLanguagesResponse.js
var payload = context.getVariable("response.content");
var payloadObj = JSON.parse(payload);
var newPayload = JSON.stringify(payloadObj.data.languages);
context.setVariable("response.content", newPayload);
EOF

cat <<EOF > ${PROXY_NAME}/apiproxy/policies/JS-BuildLanguagesResponse.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Javascript continueOnError="false" enabled="true" timeLimit="200" name="JS-BuildLanguagesResponse">
    <DisplayName>JS-BuildLanguagesResponse</DisplayName>
    <Properties/>
    <ResourceURL>jsc://JS-BuildLanguagesResponse.js</ResourceURL>
</Javascript>
EOF

echo "=== 7. Criando o arquivo de configuração principal (${PROXY_NAME}.xml) ==="
cat <<EOF > ${PROXY_NAME}/apiproxy/${PROXY_NAME}.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<APIProxy revision="1" name="${PROXY_NAME}">
    <Basepaths>/translate/v1</Basepaths>
    <ConfigurationVersion majorVersion="4" minorVersion="0"/>
    <DisplayName>${PROXY_NAME}</DisplayName>
    <Policies>
        <Policy>AM-BuildTranslateRequest</Policy>
        <Policy>AM-BuildTranslateResponse</Policy>
        <Policy>AM-BuildLanguagesRequest</Policy>
        <Policy>JS-BuildLanguagesResponse</Policy>
    </Policies>
    <ProxyEndpoints>
        <ProxyEndpoint>default</ProxyEndpoint>
    </ProxyEndpoints>
    <Resources>
        <Resource>properties://language.properties</Resource>
        <Resource>jsc://JS-BuildLanguagesResponse.js</Resource>
    </Resources>
    <TargetEndpoints>
        <TargetEndpoint>default</TargetEndpoint>
        <TargetEndpoint>languages</TargetEndpoint>
    </TargetEndpoints>
</APIProxy>
EOF

echo "=== 8. Criando o ProxyEndpoint com os Conditional Flows (default.xml) ==="
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
    <Flows>
        <Flow name="translate">
            <Description>Tradução de texto</Description>
            <Request>
                <Step>
                    <Name>AM-BuildTranslateRequest</Name>
                </Step>
            </Request>
            <Response>
                <Step>
                    <Name>AM-BuildTranslateResponse</Name>
                </Step>
            </Response>
            <Condition>(proxy.pathsuffix MatchesPath "/") and (request.verb = "POST")</Condition>
        </Flow>
        <Flow name="getLanguages">
            <Description>Listagem de linguagens suportadas</Description>
            <Request>
                <Step>
                    <Name>AM-BuildLanguagesRequest</Name>
                </Step>
            </Request>
            <Response>
                <Step>
                    <Name>JS-BuildLanguagesResponse</Name>
                </Step>
            </Response>
            <Condition>(proxy.pathsuffix MatchesPath "/languages")</Condition>
        </Flow>
    </Flows>
    <HTTPProxyConnection>
        <BasePath>/translate/v1</BasePath>
        <Properties/>
    </HTTPProxyConnection>
    <RouteRule name="languages">
        <Condition>(proxy.pathsuffix MatchesPath "/languages")</Condition>
        <TargetEndpoint>languages</TargetEndpoint>
    </RouteRule>
    <RouteRule name="default">
        <TargetEndpoint>default</TargetEndpoint>
    </RouteRule>
</ProxyEndpoint>
EOF

echo "=== 9. Criando o TargetEndpoint (default.xml) ==="
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

echo "=== 10. Criando o TargetEndpoint para Listagem de Línguas (languages.xml) ==="
cat <<EOF > ${PROXY_NAME}/apiproxy/targets/languages.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<TargetEndpoint name="languages">
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
        <URL>https://translation.googleapis.com/language/translate/v2/languages</URL>
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

echo "=== 10. Compactando o pacote do proxy ==="
cd ${PROXY_NAME}
zip -r ../${PROXY_NAME}.zip apiproxy
cd ..

echo "=== 11. Obtendo token de autenticação do Gcloud ==="
TOKEN=$(gcloud auth print-access-token)

echo "=== 12. Enviando o proxy atualizado para o Apigee (Import) ==="
curl -X POST "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/apis?name=${PROXY_NAME}&action=import" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@${PROXY_NAME}.zip" \
  -o update.json

cat update.json
REVISION=$(cat update.json | jq -r '.revision')

echo -e "\n\n=== 13. Fazendo o Deploy da nova revisão no ambiente: ${ENVIRONMENT} ==="
# Nota: sobrescreve/atualiza se necessário enviando a revisão gerada (geralmente sequencial se já existir)
curl -X POST "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/environments/${ENVIRONMENT}/apis/${PROXY_NAME}/revisions/${REVISION}/deployments?override=true" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d '{
   "serviceAccount": "'"${SERVICE_ACCOUNT}"'"
  }'

echo -e "\n\n=== Limpando arquivos temporários ==="
rm -rf ${PROXY_NAME} ${PROXY_NAME}.zip

echo "Script concluído com sucesso!"

echo "Testes:"
set -x
curl -i -k -X GET "https://eval.example.com/translate/v1/languages"
curl -i -k -X POST "https://eval.example.com/translate/v1?lang=de" -H "Content-Type:application/json" -d '{ "text": "Hello world!" }'
curl -i -k -X POST "https://eval.example.com/translate/v1" -H "Content-Type:application/json" -d '{ "text": "Hello world!" }'
set +x

#exit 0
#
#
#gcloud config set project qwiklabs-gcp-02-628c57b7e3cd
#TEST_VM_ZONE=$(gcloud compute instances list --filter="name=('apigeex-test-vm')" --format "value(zone)")
#gcloud compute ssh apigeex-test-vm --zone=${TEST_VM_ZONE} --force-key-file-overwrite
#
#
#
#Check complete. Points earned: 16. Message:
#Please create the 'AM-BuildTranslateRequest' AssignMessage policy with the correct configuration and redeploy the API proxy.
