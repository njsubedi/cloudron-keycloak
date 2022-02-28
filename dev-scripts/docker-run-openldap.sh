#!/bin/bash -e

# Run OpenLDAP & phpLDAPadmin on the network named localnet
# Create a network, if not exists: `docker network create localnet`

docker run --name ldap-service --hostname ldap-service --network localnet --detach osixia/openldap:1.1.8
docker run -p 8091:443 --name phpldapadmin-service --hostname phpldapadmin-service --network localnet --env PHPLDAPADMIN_LDAP_HOSTS=ldap-service --detach osixia/phpldapadmin:0.9.0

echo "Go to: https://localhost:8091"
echo "Login DN: cn=admin,dc=example,dc=org"
echo "Password: admin"