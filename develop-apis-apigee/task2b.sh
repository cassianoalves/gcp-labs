#!/bin/bash -x

echo "Create Proxy"

cd ~/develop-apis-apigee/rest-backend
source config.sh

# =====================================================================
# 1. DEFINIÇÃO DE VARIÁVEIS (Ajustadas dinamicamente para o seu lab)
# =====================================================================
PROJECT_ID=$GOOGLE_PROJECT_ID
PROXY_NAME="bank-v1"
ENV_NAME="eval" # Mude para "test" ou o nome do seu ambiente do Apigee se for diferente
BASE_PATH=/bank/v1

# URL real do seu Cloud Run detectada anteriormente
BACKEND_URL=$(gcloud run services describe simplebank-rest --platform managed --region $CLOUDRUN_REGION --format json | jq -r '.metadata.annotations."run.googleapis.com/urls" | fromjson[0]')

# Conta de serviço usada pelo Apigee no seu erro
SERVICE_ACCOUNT="apigee-internal-access@$PROJECT_ID.iam.gserviceaccount.com"

echo "--------------------------------------------------"
echo "Iniciando a criação do Proxy Apigee: $PROXY_NAME"
echo "Projeto: $PROJECT_ID"
echo "Destino: $BACKEND_URL"
echo "Service Account: $SERVICE_ACCOUNT"
echo "--------------------------------------------------"

# =====================================================================
# 2. CRIAR A ESTRUTURA DE DIRETÓRIOS DO APIGEE PROXY
# =====================================================================
mkdir -p apiproxy/proxies
mkdir -p apiproxy/targets

# =====================================================================
# 3. GERAR ARQUIVO DE CONFIGURAÇÃO DO TARGET ENDPOINT
# Nota: Aqui inserimos a autenticação Google OIDC correta usando a SA do lab
# =====================================================================
cat <<EOF > apiproxy/targets/default.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<TargetEndpoint name="default">
  <PreFlow name="PreFlow">
    <Request/>
    <Response/>
  </PreFlow>
  <Flows/>
  <PostFlow name="PostFlow">
    <Request/>
    <Response/>
  </PostFlow>
  <HTTPTargetConnection>
    <Properties/>
    <URL>$BACKEND_URL</URL>
    <Authentication>
      <GoogleIDToken>
        <Audience>$BACKEND_URL</Audience>
      </GoogleIDToken>
    </Authentication>
  </HTTPTargetConnection>
</TargetEndpoint>
EOF

# =====================================================================
# 4. GERAR ARQUIVO DE CONFIGURAÇÃO DO PROXY ENDPOINT
# =====================================================================
cat <<EOF > apiproxy/proxies/default.xml
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
        <BasePath>$BASE_PATH</BasePath>
        <Properties/>
    </HTTPProxyConnection>
    <RouteRule name="default">
        <TargetEndpoint>default</TargetEndpoint>
    </RouteRule>
</ProxyEndpoint>
EOF

# =====================================================================
# 5. GERAR O ARQUIVO MANIFESTO DO PROXY
# =====================================================================
cat <<EOF > apiproxy/$PROXY_NAME.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<APIProxy revision="1" name="$PROXY_NAME">
    <Basepaths>$BASE_PATH</Basepaths>
    <ConfigurationVersion>4.0</ConfigurationVersion>
    <Description/>
    <DisplayName>$PROXY_NAME</DisplayName>
    <EntryPoints/>
    <ProxyEndpoints>
        <ProxyEndpoint>default</ProxyEndpoint>
    </ProxyEndpoints>
    <Resources/>
    <TargetServers/>
    <TargetEndpoints>
        <TargetEndpoint>default</TargetEndpoint>
    </TargetEndpoints>
</APIProxy>
EOF

# =====================================================================
# 6. COMPACTAR E IMPORTAR PARA O APIGEE VIA API
# =====================================================================
echo "Compactando o pacote do proxy..."
zip -r $PROXY_NAME.zip apiproxy/ > /dev/null

# Obter token de acesso do gcloud para autenticar a chamada de API do Apigee
TOKEN=$(gcloud auth print-access-token)

echo "Importando o proxy para a organização do Apigee..."
IMPORT_RESPONSE=$(curl -X POST -H "Authorization: Bearer $TOKEN" \
  -F "file=@$PROXY_NAME.zip" \
  "https://apigee.googleapis.com/v1/organizations/$PROJECT_ID/apis?action=import&name=$PROXY_NAME" \
  -s)

# Extrair a revisão criada a partir do retorno JSON
REVISION=$(echo $IMPORT_RESPONSE | grep -o '"revision": "[^"]*' | grep -o '[0-9]*' | head -n 1)

if [ -z "$REVISION" ]; then
    echo "Falha ao importar o proxy. Resposta do servidor:"
    echo $IMPORT_RESPONSE
    exit 1
fi

echo "Proxy importado com sucesso! Revisão: $REVISION"

# =====================================================================
# 7. EXECUTAR O DEPLOY DA REVISÃO DO PROXY (Correção com Service Account no payload)
# =====================================================================
echo "Fazendo o deploy da revisão $REVISION no ambiente '$ENV_NAME'..."

# Enviando a service account explicitamente no corpo da requisição exigida pela API do Apigee
DEPLOY_RESPONSE=$(curl -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"serviceAccount\": \"$SERVICE_ACCOUNT\"}" \
  "https://apigee.googleapis.com/v1/organizations/$PROJECT_ID/environments/$ENV_NAME/apis/$PROXY_NAME/revisions/$REVISION/deployments?override=true" \
  -s)

echo "Deploy concluído!"
echo "Resposta do Apigee:"
echo $DEPLOY_RESPONSE | grep -o '"state": "[^"]*' | head -n 1

# Limpando arquivos locais temporários
rm -rf apiproxy $PROXY_NAME.zip
echo "--------------------------------------------------"
echo "Processo finalizado."