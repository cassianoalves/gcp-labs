#!/bin/bash -x

cd ~/develop-apis-apigee/rest-backend
source config.sh


#!/bin/bash

# Configurações do Ambiente (Seu Projeto do Qwiklabs)
# O script tenta pegar o ID atual de forma dinâmica se rodado no Cloud Shell
export PROJECT_ID=$GOOGLE_CLOUD_PROJECT
export ENV="eval"
export AUTH="Authorization: Bearer $(gcloud auth print-access-token)"
export SF_NAME="get-address-for-location"

echo "=== Iniciando criação do Shared Flow Corrigido: $SF_NAME ==="
echo "Projeto Alvo: $PROJECT_ID"

# 1. Criação da Estrutura de Diretórios Padronizada do Apigee
mkdir -p sharedflowbundle/sharedflows
mkdir -p sharedflowbundle/policies

# 2. Criando o Manifesto Principal EXATAMENTE igual ao export do Console
cat <<EOF > sharedflowbundle/$SF_NAME.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<SharedFlowBundle revision="1" name="$SF_NAME">
   <DisplayName/>
   <Description/>
   <SharedFlows>
     <SharedFlow>default</SharedFlow>
   </SharedFlows>
   <subType>SharedFlow</subType>
   <Policies>
     <Policy>LC-LookupAddress</Policy>
     <Policy>SC-GoogleGeocode</Policy>
     <Policy>EV-ExtractAddress</Policy>
     <Policy>PC-StoreAddress</Policy>
   </Policies>
</SharedFlowBundle>
EOF

# 3. Criando as Políticas (Policies) individuais com cabeçalhos estruturados
# 3.1 Lookup Cache
cat <<EOF > sharedflowbundle/policies/LC-LookupAddress.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<LookupCache continueOnError="false" enabled="true" name="LC-LookupAddress">
  <CacheResource>AddressesCache</CacheResource>
  <Scope>Exclusive</Scope>
  <CacheKey>
    <KeyFragment ref="geocoding.latitude"/>
    <KeyFragment ref="geocoding.longitude"/>
  </CacheKey>
  <AssignTo>geocoding.address</AssignTo>
</LookupCache>
EOF

# 3.2 Service Callout
cat <<EOF > sharedflowbundle/policies/SC-GoogleGeocode.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<ServiceCallout continueOnError="false" enabled="true" name="SC-GoogleGeocode">
  <Request>
    <Set>
      <QueryParams>
        <QueryParam name="latlng">{geocoding.latitude},{geocoding.longitude}</QueryParam>
        <QueryParam name="key">{geocoding.apikey}</QueryParam>
      </QueryParams>
      <Verb>GET</Verb>
    </Set>
  </Request>
  <Response>calloutResponse</Response>
  <HTTPTargetConnection>
    <URL>https://maps.googleapis.com/maps/api/geocode/json</URL>
  </HTTPTargetConnection>
</ServiceCallout>
EOF

# 3.3 Extract Variables
cat <<EOF > sharedflowbundle/policies/EV-ExtractAddress.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<ExtractVariables continueOnError="false" enabled="true" name="EV-ExtractAddress">
  <IgnoreUnresolvedVariables>true</IgnoreUnresolvedVariables>
  <JSONPayload>
    <Variable name="address">
      <JSONPath>$.results[0].formatted_address</JSONPath>
    </Variable>
  </JSONPayload>
  <Source clearPayload="false">calloutResponse.content</Source>
  <VariablePrefix>geocoding</VariablePrefix>
</ExtractVariables>
EOF

# 3.4 Populate Cache
cat <<EOF > sharedflowbundle/policies/PC-StoreAddress.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<PopulateCache continueOnError="false" enabled="true" name="PC-StoreAddress">
  <CacheResource>AddressesCache</CacheResource>
  <Scope>Exclusive</Scope>
  <Source>geocoding.address</Source>
  <CacheKey>
    <KeyFragment ref="geocoding.latitude"/>
    <KeyFragment ref="geocoding.longitude"/>
  </CacheKey>
  <ExpirySettings>
    <TimeoutInSec>3600</TimeoutInSec>
  </ExpirySettings>
</PopulateCache>
EOF

# 4. Criando o fluxo sequencial padrão (default.xml)
cat <<EOF > sharedflowbundle/sharedflows/default.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<SharedFlow name="default">
  <Step>
    <Name>LC-LookupAddress</Name>
  </Step>
  <Step>
    <Condition>lookupcache.LC-LookupAddress.cachehit == false</Condition>
    <Name>SC-GoogleGeocode</Name>
  </Step>
  <Step>
    <Condition>lookupcache.LC-LookupAddress.cachehit == false</Condition>
    <Name>EV-ExtractAddress</Name>
  </Step>
  <Step>
    <Condition>lookupcache.LC-LookupAddress.cachehit == false</Condition>
    <Name>PC-StoreAddress</Name>
  </Step>
</SharedFlow>
EOF

echo "-> Estrutura local idêntica ao export gerada. Compactando bundle..."

# 5. Compactando em arquivo ZIP mantendo estritamente a árvore interna do seu zip
rm -f sharedflowbundle.zip
zip -r sharedflowbundle.zip sharedflowbundle/ > /dev/null

echo "-> Importando pacote na API do Apigee..."

# 6. Importação para a Organização
RESPONSE=$(curl -s -X POST \
  -H "$AUTH" \
  -F "file=@sharedflowbundle.zip" \
  "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/sharedflows?name=${SF_NAME}&action=import")

REVISION=$(echo "$RESPONSE" | grep -oP '"revision":\s*"\K[^"]+')

if [ -z "$REVISION" ]; then
    echo "Erro ao importar. Resposta da API:"
    echo "$RESPONSE"
    exit 1
fi

echo "-> Importado com sucesso como Revisão $REVISION."
echo "-> Executando deploy sem Service Account..."

# 7. Executando o Deploy no ambiente exigido
DEPLOY_RESPONSE=$(curl -s -X POST \
  -H "$AUTH" \
  "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/environments/${ENV}/sharedflows/${SF_NAME}/revisions/${REVISION}/deployments")

echo "=== Processo Concluído! ==="
echo "$DEPLOY_RESPONSE" | grep -E "state|revision" || echo "$DEPLOY_RESPONSE"

# Limpeza dos temporários
rm -rf sharedflowbundle sharedflowbundle.zip