#!/bin/sh

VERSION=1.0.0
DOMAIN='<domain in cloudron to install this app>'
AUTHOR='<your name>'

docker build -t $AUTHOR/cloudron-keycloak:$VERSION ./ && docker push $AUTHOR/cloudron-keycloak:$VERSION

cloudron install --image $AUTHOR/cloudron-keycloak:$VERSION -l $DOMAIN

cloudron logs -f --app $DOMAIN
