ifneq ($(wildcard .env),)
    include .env
    export
endif

run:
	npx electron client

install-schema:
	cat ./db/schema.sql | docker compose exec -T db /opt/mssql-tools18/bin/sqlcmd \
		-S localhost \
		-U $(DB_USER) \
		-P '$(DB_PASSWORD)' \
		-C

start-services:
	docker compose up -d --wait

start:
	make start-services
	make install-schema
	make run