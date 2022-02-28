#!/bin/bash
set -eu pipefail

export KC_HOSTNAME="$CLOUDRON_APP_DOMAIN"
export KC_HTTP_ENABLED="true"

pg_cli() {
  PGPASSWORD=$CLOUDRON_POSTGRESQL_PASSWORD psql \
    -h $CLOUDRON_POSTGRESQL_HOST \
    -p $CLOUDRON_POSTGRESQL_PORT \
    -U $CLOUDRON_POSTGRESQL_USERNAME \
    -d $CLOUDRON_POSTGRESQL_DATABASE -c "$1"
}

KC_NEW_REALM=cloudron

# Check for First Run
if [[ ! -f /app/data/conf/keycloak.conf ]]; then
  echo "First run"

  mkdir -p /app/data/themes /app/data/providers /app/data/conf /app/data/tmp
  cp -R /app/code/themes-orig/* /app/data/themes/
  cp -R /app/code/providers-orig/* /app/data/providers/
  cp -R /app/code/conf-orig/* /app/data/conf/
  chown -R 1000:1000 /app/data/

  /app/code/first_run.sh

  touch /app/data/conf/keycloak.conf

  echo "#Basic settings to run Keycloak in production" >/app/data/conf/keycloak.conf
fi

# These values should be re-set to make Keycloak work
echo "Setting ENV variables to /app/data/conf/keycloak.conf"
crudini --set /app/data/conf/keycloak.conf "" db-username "$CLOUDRON_POSTGRESQL_USERNAME"
crudini --set /app/data/conf/keycloak.conf "" db-password "$CLOUDRON_POSTGRESQL_PASSWORD"
crudini --set /app/data/conf/keycloak.conf "" db-url "jdbc:postgresql://$CLOUDRON_POSTGRESQL_HOST/$CLOUDRON_POSTGRESQL_DATABASE"
crudini --set /app/data/conf/keycloak.conf "" http-enabled "true"
crudini --set /app/data/conf/keycloak.conf "" hostname "$CLOUDRON_APP_DOMAIN"
crudini --set /app/data/conf/keycloak.conf "" http-host "0.0.0.0"
crudini --set /app/data/conf/keycloak.conf "" http-port 8080
crudini --set /app/data/conf/keycloak.conf "" proxy "edge"
crudini --set /app/data/conf/keycloak.conf "" proxy-address-forwarding "true"
crudini --set /app/data/conf/keycloak.conf "" hostname-strict "true"
crudini --set /app/data/conf/keycloak.conf "" cache "local"

# Check for SMTP Configuration
pg_cli "DELETE FROM public.realm_smtp_config WHERE realm_id='$KC_NEW_REALM';"
if [[ -z "${CLOUDRON_MAIL_SMTP_SERVER+x}" ]]; then
  echo "SMTP disabled."
else
  echo "SMTP enabled. Setting up SMTP Server values..."

  pg_cli "INSERT INTO public.realm_smtp_config (realm_id, value, name) VALUES ('$KC_NEW_REALM', '$CLOUDRON_MAIL_SMTP_SERVER', 'host');"
  pg_cli "INSERT INTO public.realm_smtp_config (realm_id, value, name) VALUES ('$KC_NEW_REALM', '$CLOUDRON_MAIL_SMTP_PORT', 'port');"
  pg_cli "INSERT INTO public.realm_smtp_config (realm_id, value, name) VALUES ('$KC_NEW_REALM', '$CLOUDRON_MAIL_SMTP_USERNAME ', 'user');"
  pg_cli "INSERT INTO public.realm_smtp_config (realm_id, value, name) VALUES ('$KC_NEW_REALM', '$CLOUDRON_MAIL_SMTP_PASSWORD', 'password');"
  pg_cli "INSERT INTO public.realm_smtp_config (realm_id, value, name) VALUES ('$KC_NEW_REALM', '$CLOUDRON_MAIL_FROM', 'from');"
  pg_cli "INSERT INTO public.realm_smtp_config (realm_id, value, name) VALUES ('$KC_NEW_REALM', '$CLOUDRON_MAIL_FROM', 'envelopeFrom');"
  pg_cli "INSERT INTO public.realm_smtp_config (realm_id, value, name) VALUES ('$KC_NEW_REALM', '$CLOUDRON_MAIL_FROM', 'replyTo');"
  pg_cli "INSERT INTO public.realm_smtp_config (realm_id, value, name) VALUES ('$KC_NEW_REALM', '', 'starttls');"
  pg_cli "INSERT INTO public.realm_smtp_config (realm_id, value, name) VALUES ('$KC_NEW_REALM', '', 'ssl');"
  pg_cli "INSERT INTO public.realm_smtp_config (realm_id, value, name) VALUES ('$KC_NEW_REALM', 'true', 'auth');"
fi

# Limit memory usage of Java. See https://docs.cloudron.io/packaging/cheat-sheet/#java
if [[ -f /sys/fs/cgroup/memory/memory.memsw.limit_in_bytes ]]; then
  ALLOWED_MBYTES=$(($(cat /sys/fs/cgroup/memory/memory.memsw.limit_in_bytes) / 2 ** 20))
else
  ALLOWED_MBYTES=1024
fi

if [[ -z "${JAVA_OPTS_APPEND+x}" ]]; then
  export JAVA_OPTS_APPEND="-XX:MaxRAM=${ALLOWED_MBYTES}M"
else
  export JAVA_OPTS_APPEND="-XX:MaxRAM=${ALLOWED_MBYTES}M $JAVA_OPTS"
fi

echo "JAVA_OPTS_APPEND: $JAVA_OPTS_APPEND"

chown -R cloudron:cloudron /app/data/

/usr/local/bin/gosu cloudron:cloudron /app/code/bin/kc.sh -cf /app/data/conf/keycloak.conf start
