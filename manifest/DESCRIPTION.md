Run Keycloak on Cloudron. The default *master* realm is set up to use Cloudron LDAP for user federation.

Features
---
- Configured to use Cloudron LDAP for user federation
- Configured to use Cloudron SMTP for email

Optimizations
--
- Uses recommended LDAP search filter to log in with email/username
- Sets the recommended custom JVM options to fix java memory issues
- Properly maps the givenName property with firstName to work with Cloudron LDAP