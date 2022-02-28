#!/bin/sh

# Run `postgres` container named `postgres` in docker network `localnet`
# Create a network, if not exists: `docker network create localnet`

docker run --name postgres -d -p 5432:5432 --network localnet \
	-e POSTGRES_USER=user \
	-e POSTGRES_PASSWORD=password \
	-e POSTGRES_DB=keycloak \
	postgres:latest


# Login to pg cli
PGPASSWORD=postgres psql -h 127.0.0.1 -U postgres -p 5432

# Recreate database quickly.
drop database keycloak;
create database keycloak with encoding 'utf-8' owner postgres;
