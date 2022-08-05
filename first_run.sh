#!/bin/bash
set -eu pipefail

pg_cli() {
  PGPASSWORD=$CLOUDRON_POSTGRESQL_PASSWORD psql \
    -h $CLOUDRON_POSTGRESQL_HOST \
    -p $CLOUDRON_POSTGRESQL_PORT \
    -U $CLOUDRON_POSTGRESQL_USERNAME \
    -d $CLOUDRON_POSTGRESQL_DATABASE -c "$1"
}

export KEYCLOAK_HOME=/app/code
export KEYCLOAK_ADMIN=keycloakadmin
export KEYCLOAK_ADMIN_PASSWORD=keycloakadminpassword

echo "Start keycloak with default params"
/usr/local/bin/gosu cloudron:cloudron /app/code/bin/kc.sh start --optimized \
  --db-url "jdbc:postgresql://$CLOUDRON_POSTGRESQL_HOST/$CLOUDRON_POSTGRESQL_DATABASE" \
  --db-username "$CLOUDRON_POSTGRESQL_USERNAME" \
  --db-password "$CLOUDRON_POSTGRESQL_PASSWORD" >/app/data/firstrun.log &

echo "Waiting for the server to start..."

(tail -f -n0 /app/data/firstrun.log &) | grep -q "Listening on:"

echo ">>> Server started. Removing temporary log & waiting for a few seconds..."
rm -f /app/data/firstrun.log
sleep 2

echo "Generate an Admin token using the default admin credentials"
KC_ADMIN_TOKEN_API="http://localhost:8080/realms/master/protocol/openid-connect/token"
KC_ADMIN_API="http://localhost:8080/admin"
KC_ADMIN_TOKEN=$(curl -s -X POST "$KC_ADMIN_TOKEN_API" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=$KEYCLOAK_ADMIN" \
  -d "password=$KEYCLOAK_ADMIN_PASSWORD" \
  -d 'grant_type=password' \
  -d 'client_id=admin-cli' | jq -r '.access_token')

echo "Create a new Realm because the default master realm is only recommended for managing Keycloak itself."

KC_REALM=cloudron
KC_REALM_API="http://localhost:8080/admin/realms/$KC_REALM"
curl -s -X POST "$KC_ADMIN_API/realms" \
  -H "Content-Type: application/json;charset=utf-8" \
  -H "Authorization: Bearer $KC_ADMIN_TOKEN" \
  -d '{"enabled":true, "id":"'"$KC_REALM"'", "realm":"'"$KC_REALM"'"}'

echo "Realm created"

echo "Setting SMTP Config..."

CLOUDRON_SMTP_SETTINGS='{
  "host": "'"$CLOUDRON_MAIL_SMTP_SERVER"'",
  "port": "'"$CLOUDRON_MAIL_SMTP_PORT"'",
  "from": "'"$CLOUDRON_MAIL_SMTP_USERNAME"'",
  "fromDisplayName": "'"$CLOUDRON_APP_DOMAIN"'",
  "envelopeFrom": "'"$CLOUDRON_MAIL_SMTP_USERNAME"'",
  "replyTo": "'"$CLOUDRON_MAIL_SMTP_USERNAME"'",
  "replyToDisplayName": "'"$CLOUDRON_APP_DOMAIN"'",
  "auth": "true",
  "user": "'"$CLOUDRON_MAIL_SMTP_USERNAME"'",
  "password": "'"$CLOUDRON_MAIL_SMTP_PASSWORD"'",
  "ssl": "",
  "starttls": ""
}'

# Fetch the current realm information.
REALM_JSON=$(curl -s -X GET "$KC_REALM_API" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer $KC_ADMIN_TOKEN" | jq -r .)

echo "Fetched existing Realm Config"

# Replace the Realm's 'smtpServer' with Cloudron SMTP Setting
NEW_REALM_JSON=$(echo "$REALM_JSON" | jq --argjson ARG_SMTP_JSON "$CLOUDRON_SMTP_SETTINGS" '.smtpServer |= $ARG_SMTP_JSON')

curl -s -X PUT "$KC_REALM_API" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json;charset=utf-8" \
  -H "Authorization: Bearer $KC_ADMIN_TOKEN" \
  -d "$NEW_REALM_JSON"

echo "Modified SMTP Configuration successfully"
echo "Done SMTP Config"

echo "Adding LDAP Provider"

LDAP_PROVIDER_NAME='Cloudron LDAP'
LDAP_FILTER='(objectclass=user)'
LDAP_OBJECT_CLASSES='user,inetorgperson,person'
LDAP_USERNAME_ATTRIBUTE='username'
LDAP_RDN_ATTRIBUTE='uid'
LDAP_UUID_ATTRIBUTE='entryUUID'
LDAP_VENDOR='ad'
LDAP_FIRSTNAME_MAPPER='givenName'

# Only create new provider if none exist.
echo "Checking for existing LDAP providers"
COUNT_LDAP_PROVIDERS_RAW=$(pg_cli "SELECT count(id) FROM component WHERE parent_id='$KC_REALM' and provider_id='ldap' and provider_type='org.keycloak.storage.UserStorageProvider';")
COUNT_LDAP_PROVIDERS=$(echo "$COUNT_LDAP_PROVIDERS_RAW" | head -n 3 | tail -n 1 | xargs)

if [[ "$COUNT_LDAP_PROVIDERS" -eq 0 ]]; then
  # NOTE: After adding a LDAP Provider in Keycloak, the first name of the user is mapped to "cn",  so we need to re-map
  # firstName to givenName. Otherwise, a user named John Doe with uerid 'uid-foobar' will be read as "uid-foobar Joe" by Keycloak.

  # Create a provider, and grab the component ID.
  # This request responds with a "location" header, with the newly created component ID. eg:
  # HTTP/1.1 201 Created
  # ...
  # location: $KC_REALM_API/components/component-id
  # ...
  NEW_LDAP_REQUEST=$(curl -s -D - -X POST "$KC_REALM_API/components" \
    -H "Content-Type: application/json;charset=utf-8" \
    -H "Authorization: Bearer $KC_ADMIN_TOKEN" \
    -d '
    {
      "name":"'"$LDAP_PROVIDER_NAME"'",
      "parentId":"'"$KC_REALM"'",
      "providerId":"ldap",
      "providerType":"org.keycloak.storage.UserStorageProvider",
      "config":{
        "vendor":["'"$LDAP_VENDOR"'"],
        "usernameLDAPAttribute":["'"$LDAP_USERNAME_ATTRIBUTE"'"],
        "rdnLDAPAttribute":["'"$LDAP_RDN_ATTRIBUTE"'"],
        "uuidLDAPAttribute":["'"$LDAP_UUID_ATTRIBUTE"'"],
        "userObjectClasses":["'"$LDAP_OBJECT_CLASSES"'"],
        "customUserSearchFilter":["'"$LDAP_FILTER"'"],
        "connectionUrl":["'"$CLOUDRON_LDAP_URL"'"],
        "usersDn":["'"$CLOUDRON_LDAP_USERS_BASE_DN"'"],
        "bindDn":["'"$CLOUDRON_LDAP_BIND_DN"'"],
        "bindCredential":["'"$CLOUDRON_LDAP_BIND_PASSWORD"'"],
        "enabled":["true"],"priority":["0"],"authType":["simple"],"startTls":[],"fullSyncPeriod":["-1"],"changedSyncPeriod":["-1"],"cachePolicy":["DEFAULT"],"evictionDay":[],"evictionHour":[],"evictionMinute":[],"maxLifespan":[],"batchSizeForSync":["1000"],"editMode":["READ_ONLY"],"importEnabled":["false"],"syncRegistrations":["false"],"usePasswordModifyExtendedOp":[],"searchScope":["1"],"validatePasswordPolicy":["false"],"trustEmail":["true"],"useTruststoreSpi":["ldapsOnly"],"connectionPooling":["true"],"connectionPoolingAuthentication":[],"connectionPoolingDebug":[],"connectionPoolingInitSize":[],"connectionPoolingMaxSize":[],"connectionPoolingPrefSize":[],"connectionPoolingProtocol":[],"connectionPoolingTimeout":[],"connectionTimeout":[],"readTimeout":[],"pagination":["true"],"allowKerberosAuthentication":["false"],"serverPrincipal":[],"keyTab":[],"kerberosRealm":[],"debug":["false"],"useKerberosForPasswordAuthentication":["false"]
      }
    }')

  echo "New LDAP Provider Created"

  # Grab the id from the "Location" header, and remove trailing carriage return from the id
  NEW_LDAP_PROVIDER_ID=$(echo "$NEW_LDAP_REQUEST" | grep -Fi 'Location:' | sed "s|Location: $KC_REALM_API/components/||" | sed "s|\r||g")

  # Fetch the "LDAP Mappers" Component for the newly created LDAP Provider.
  # Response contains all mappers in the form [{id:'',name:'',providerId:'',providerType:'',parentId:'',config:{}}]
  LDAP_MAPPERS=$(curl -s \
    -H "Accept: application/json;charset=utf-8" \
    -H "Authorization: Bearer $KC_ADMIN_TOKEN" \
    "$KC_REALM_API/components?type=org.keycloak.storage.ldap.mappers.LDAPStorageMapper&parent=$NEW_LDAP_PROVIDER_ID")

  echo "Fetched existing LDAP Mappers"

  # We are only interested in the mapper with the name "first name".
  FIRSTNAME_MAPPER_ID=$(echo "$LDAP_MAPPERS" | jq -r '.[] | select(.name=="first name") | .id')
  FIRSTNAME_MAPPER_PARENT_ID=$(echo "$LDAP_MAPPERS" | jq -r '.[] | select(.name=="first name") | .parentId')

  # Modify the "first name" LDAP Mapper to map "firstName" -> "givenName".
  curl -X PUT "$KC_REALM_API/components/$FIRSTNAME_MAPPER_ID" \
    -H "Content-Type: application/json;charset=utf-8" \
    -H "Authorization: Bearer $KC_ADMIN_TOKEN" \
    -d '{
        "id":"'"$FIRSTNAME_MAPPER_ID"'",
        "name":"first name",
        "providerId":"user-attribute-ldap-mapper",
        "providerType":"org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
        "parentId":"'"$FIRSTNAME_MAPPER_PARENT_ID"'",
        "config":{
          "ldap.attribute":["'"$LDAP_FIRSTNAME_MAPPER"'"],"is.mandatory.in.ldap":["true"],"always.read.value.from.ldap":["true"],"read.only":["true"],"user.model.attribute":["firstName"],"attribute.default.value":[],"is.binary.attribute":["false"]
        }
    }'
  echo "Modified LDAP Mapper to map firstName -> givenName"
else
  echo "LDAP provider already exists!"
fi

echo "first run setup complete. restarting keycloak as usual."
killall java
