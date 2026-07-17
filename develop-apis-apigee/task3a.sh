#!/bin/bash -x

cd ~/develop-apis-apigee/rest-backend
source config.sh

gcloud services enable geocoding-backend.googleapis.com

export API_KEY=$(gcloud alpha services api-keys create --project=${GOOGLE_CLOUD_PROJECT} --display-name="Geocoding API key for Apigee" --api-target=service=geocoding_backend --format "value(response.keyString)")
echo "export API_KEY=${API_KEY}" >> ~/.bashrc
echo "API_KEY=${API_KEY}"

curl "https://maps.googleapis.com/maps/api/geocode/json?key=${API_KEY}&latlng=37.404934,-122.021411"