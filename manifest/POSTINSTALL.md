After installation, open the Terminal and run the following command to add the initial admin named "keycloakadmin", and set a new password for that user. Change "keycloakadmin" to something else if you desire, but it's a good idea not to set a username like "admin", that can conflict with an existing user in your Cloudron.

`/opt/jboss/keycloak/bin/add-user-keycloak.sh -u keycloakadmin`

You must restart the app from the dashboard or run the following command to restart the server before the newly created user can log in.

`/opt/jboss/keycloak/bin/jboss-cli.sh --connect --command=:reload`

