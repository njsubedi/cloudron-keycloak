#!/bin/sh
# Uncomment for Fresh Run
docker rm -f keycloak_custom

# Build with detailed output
DOCKER_BUILDKIT=0 docker build -t keycloak_custom .

# Run in an environment similar to Cloudron.
# Must access using nginx or similar reverse proxy.

BUILDKIT_PROGRESS=plain docker build -t keycloak_custom . &&
docker run --read-only \
  -v "$(pwd)"/.docker/app/data:/app/data:rw \
  -v "$(pwd)"/.docker/tmp:/tmp:rw \
  -v "$(pwd)"/.docker/run:/run:rw \
  -p 8080:8080 \
  --network localnet \
  -e KC_DB_URL_DATABASE=keycloak \
  -e KC_DB_URL_HOST=172.17.0.1 \
  -e KC_DB_URL_PORT=5432 \
  -e KC_DB_USERNAME=postgres \
  -e KC_DB_PASSWORD=postgres \
  -e KC_DB=postgres \
  -e KC_HOSTNAME=keycloak.localhost \
  -e KC_HTTP_HOST=0.0.0.0 \
  -e KC_HTTP_PORT=8080 \
  -e KEYCLOAK_ADMIN=keycloakadmin \
  -e KEYCLOAK_ADMIN_PASSWORD=keycloakadminpassword \
  -e KC_HTTP_ENABLED=true \
  -e KC_STRICT_HTTPS=true \
  keycloak_custom