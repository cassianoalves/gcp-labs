#!/bin/bash

# Configurações - Substitua com os seus dados
PROJECT_ID=$GOOGLE_CLOUD_PROJECT
ENVIRONMENT="eval"
PROXY_NAME="translate-v1"
SERVICE_ACCOUNT=apigee-proxy@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com
PROJECT_NUMBER=$(gcloud projects describe $GOOGLE_CLOUD_PROJECT --format="value(projectNumber)")


echo "=== 1. Reestruturando Diretórios ==="
rm -rf ${PROXY_NAME} ${PROXY_NAME}.zip
mkdir -p ${PROXY_NAME}/apiproxy/proxies
mkdir -p ${PROXY_NAME}/apiproxy/targets
mkdir -p ${PROXY_NAME}/apiproxy/policies
mkdir -p ${PROXY_NAME}/apiproxy/properties
mkdir -p ${PROXY_NAME}/apiproxy/resources/jsc

# Reaproveitando as configurações de arquivos estáticos anteriores
cat <<EOF > ${PROXY_NAME}/apiproxy/properties/language.properties.properties
output=es
caller=en
EOF

cat <<EOF > ${PROXY_NAME}/apiproxy/resources/jsc/JS-BuildLanguagesResponse.js
var payload = context.getVariable("response.content");
var payloadObj = JSON.parse(payload);
var newPayload = JSON.stringify(payloadObj.data.languages);
context.setVariable("response.content", newPayload);
EOF

# Políticas do cenário anterior
cat <<EOF > ${PROXY_NAME}/apiproxy/policies/AM-BuildTranslateRequest.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<AssignMessage continueOnError="false" enabled="true" name="AM-BuildTranslateRequest">
    <DisplayName>AM-BuildTranslateRequest</DisplayName>
    <AssignVariable>
        <Name>text</Name>
        <Template>{jsonPath($.text,request.content)}</Template>
    </AssignVariable>
    <AssignVariable>
        <Name>language</Name>
        <Template>{firstnonnull(request.queryparam.lang,propertyset.language.properties.output)}</Template>
    </AssignVariable>
    <Set>
        <Payload contentType="application/json">{"q": "{text}", "target": "{language}"}</Payload>
    </Set>
    <AssignTo createNew="false" transport="http" type="request"/>
</AssignMessage>
EOF

cat <<EOF > ${PROXY_NAME}/apiproxy/policies/AM-BuildTranslateResponse.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<AssignMessage continueOnError="false" enabled="true" name="AM-BuildTranslateResponse">
    <DisplayName>AM-BuildTranslateResponse</DisplayName>
    <AssignVariable>
        <Name>translated</Name>
        <Template>{jsonPath($.data.translations[0].translatedText,response.content)}</Template>
    </AssignVariable>
    <Set>
        <Payload contentType="application/json">{"translated": "{translated}"}</Payload>
    </Set>
    <AssignTo createNew="true" transport="http" type="response"/>
</AssignMessage>
EOF

cat <<EOF > ${PROXY_NAME}/apiproxy/policies/AM-BuildLanguagesRequest.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<AssignMessage continueOnError="false" enabled="true" name="AM-BuildLanguagesRequest">
    <DisplayName>AM-BuildLanguagesRequest</DisplayName>
    <Set>
        <Verb>POST</Verb>
        <Payload contentType="application/json">{"target": "{propertyset.language.properties.caller}"}</Payload>
    </Set>
    <AssignTo createNew="true" transport="http" type="request"/>
</AssignMessage>
EOF

cat <<EOF > ${PROXY_NAME}/apiproxy/policies/JS-BuildLanguagesResponse.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<JavaScript continueOnError="false" enabled="true" timeLimit="200" name="JS-BuildLanguagesResponse">
    <DisplayName>JS-BuildLanguagesResponse</DisplayName>
    <ResourceURL>jsc://JS-BuildLanguagesResponse.js</ResourceURL>
</JavaScript>
EOF

echo "=== 2. Criando a Nova Política VA-VerifyKey ==="
cat <<EOF > ${PROXY_NAME}/apiproxy/policies/VA-VerifyKey.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<VerifyAPIKey continueOnError="false" enabled="true" name="VA-VerifyKey">
    <DisplayName>VA-VerifyKey</DisplayName>
    <APIKey ref="request.header.Key"/>
</VerifyAPIKey>
EOF

echo "=== 3. Criando a Nova Política Q-EnforceQuota ==="
cat <<EOF > ${PROXY_NAME}/apiproxy/policies/Q-EnforceQuota.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Quota continueOnError="false" enabled="true" name="Q-EnforceQuota" type="calendar">
    <DisplayName>Q-EnforceQuota</DisplayName>
    <Allow count="5"/>
    <Interval>1</Interval>
    <TimeUnit>hour</TimeUnit>
    <StartTime>2026-01-01 00:00:00</StartTime>
    <Distributed>true</Distributed>
    <Synchronous>true</Synchronous>
    <UseQuotaConfigInAPIProduct>
        <DefaultConfig/>
    </UseQuotaConfigInAPIProduct>
</Quota>
EOF

echo "=== 4. Atualizando o ProxyEndpoint com Segurança no PreFlow (default.xml) ==="
cat <<EOF > ${PROXY_NAME}/apiproxy/proxies/default.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<ProxyEndpoint name="default">
    <Description/>
    <FaultRules/>
    <PreFlow name="PreFlow">
        <Request>
            <Step>
                <Name>VA-VerifyKey</Name>
            </Step>
            <Step>
                <Name>Q-EnforceQuota</Name>
            </Step>
        </Request>
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
    <RouteRule name="default">
        <TargetEndpoint>default</TargetEndpoint>
    </RouteRule>
</ProxyEndpoint>
EOF

# Alvo e manifesto base permanecem os mesmos
cat <<EOF > ${PROXY_NAME}/apiproxy/targets/default.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<TargetEndpoint name="default">
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

cat <<EOF > ${PROXY_NAME}/apiproxy/${PROXY_NAME}.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<APIProxy revision="2" name="${PROXY_NAME}">
    <Basepaths>/translate/v1</Basepaths>
    <ConfigurationVersion majorVersion="4" minorVersion="0"/>
    <DisplayName>${PROXY_NAME}</DisplayName>
    <Policies>
        <Policy>AM-BuildTranslateRequest</Policy>
        <Policy>AM-BuildTranslateResponse</Policy>
        <Policy>AM-BuildLanguagesRequest</Policy>
        <Policy>JS-BuildLanguagesResponse</Policy>
        <Policy>VA-VerifyKey</Policy>
        <Policy>Q-EnforceQuota</Policy>
    </Policies>
    <ProxyEndpoints>
        <ProxyEndpoint>default</ProxyEndpoint>
    </ProxyEndpoints>
    <Resources>
        <Resource>jsc://JS-BuildLanguagesResponse.js</Resource>
    </Resources>
    <TargetEndpoints>
        <TargetEndpoint>default</TargetEndpoint>
    </TargetEndpoints>
</APIProxy>
EOF

echo "=== 5. Compactando e fazendo upload da Revisão 2 ==="
cd ${PROXY_NAME}
zip -r ../${PROXY_NAME}.zip apiproxy > /dev/null
cd ..

TOKEN=$(gcloud auth print-access-token)

# Importa como uma nova revisão
curl -X POST "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/apis?name=${PROXY_NAME}&action=import" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@${PROXY_NAME}.zip"

echo -e "\n\n=== 6. Deploy da Revisão 2 no ambiente '${ENVIRONMENT}' ==="
curl -X POST "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/environments/${ENVIRONMENT}/apis/${PROXY_NAME}/revisions/2/deployments?override=true" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d '{
   "serviceAccount": "'"${SERVICE_ACCOUNT}"'"
  }'

rm -rf ${PROXY_NAME} ${PROXY_NAME}.zip
echo -e "\n\nProxy atualizado e implantado com sucesso sob a Revisão 2!"