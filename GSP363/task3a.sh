#!/bin/bash

# Configurações - Substitua com os seus dados
PROJECT_ID=$GOOGLE_CLOUD_PROJECT
ENV="eval"
PROXY_NAME="translate-v1"
SERVICE_ACCOUNT=apigee-proxy@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com
PROJECT_NUMBER=$(gcloud projects describe $GOOGLE_CLOUD_PROJECT --format="value(projectNumber)")


echo "=== Obtendo Token de Autenticação ==="
TOKEN=$(gcloud auth print-access-token)

echo "=== 1. Criando o API Product (translate-product) ==="
curl -X POST "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/apiproducts" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
        "name": "translate-product",
        "displayName": "translate-product",
        "approvalType": "auto",
        "attributes": [
          {
            "name": "access",
            "value": "public"
          }
        ],
        "apiResources": [
          "/"
        ],
        "environments": [
          "'"${ENV}"'"
        ],
        "proxies": [
          "translate-v1"
        ],
        "quota": "10",
        "quotaInterval": "1",
        "quotaTimeUnit": "minute",
        "operationGroup": {
          "operationConfigs": [
            {
              "apiSource": "translate-v1",
              "operations": [
                {
                  "resource": "/",
                  "methods": [
                    "GET",
                    "POST"
                  ]
                }
              ],
              "quota": {
                "limit": "100",
                "interval": "1",
                "timeUnit": "minute"
              }
            }
          ],
          "operationConfigType": "proxy"
        }
      }'

echo -e "\n\n=== 2. Criando o Developer (joe@example.com) ==="
curl -X POST "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/developers" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "joe@example.com",
    "firstName": "Joe",
    "lastName": "Doe",
    "userName": "joedoe"
  }'

echo -e "\n\n=== 3. Criando o Developer App (translate-app) ==="
curl -X POST "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/developers/joe@example.com/apps" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
        "name": "translate-app",
        "displayName": "translate-app",
        "developerEmail": "joe@example.com",
        "callbackUrl": "",
        "apiProducts": [
          "translate-product"
        ],
        "expiryType": "never"
      }'

echo -e "\n\n=== 4. Extraindo a Chave de API (Consumer Key) para testes ==="
API_KEY=$(curl -s -X GET "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/developers/joe@example.com/apps/translate-app" \
  -H "Authorization: Bearer ${TOKEN}" | grep -o '"consumerKey": "[^"]*' | head -n 1 | grep -o '[^"]*$')

echo -e "\n--------------------------------------------------"
echo "CONFIGURAÇÃO CONCLUÍDA!"
echo "Use esta chave para a variável \$KEY nos seus testes:"
echo "KEY=$API_KEY"
echo "--------------------------------------------------"
export API_KEY