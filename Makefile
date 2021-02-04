DOCKER_COMPOSE_FILE := docker-compose.yml


# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

init: composer-install docker-rebuild wait-healthy drupal-init docker-status
status: docker-status
start: docker-start
stop: docker-stop
restart: docker-restart
destroy: drupal-files-purge docker-destroy
rebuild: destroy init
wait-healthy:
	@echo "Wait for all containers to become healthy."
	@python $(CURDIR)/scripts/docker-compose-wait.py
update: stop composer-install docker-rebuild wait-healthy drupal-cache-clear drupal-config-import drupal-updb drupal-cache-clear
safe-update: stop composer-install docker-rebuild wait-healthy drupal-cache-clear drupal-updb drupal-cache-clear
clean: destroy
	@echo "Removing docker images. This process can be extended to do other things."
	docker rmi mobomo/mobomou-{db,php,web,memcached}:latest \
	|| true
fix-permissions:
	$(CURDIR)/bin/host-tool \
					chown $(shell id -u) ./
	$(CURDIR)/bin/host-tool \
					chmod u=rwx,g=rwxs,o=rx ./
	$(CURDIR)/bin/host-tool \
					find ./ -not -path "web/sites/default/files*" -exec chown $(shell id -u) {} \;
	$(CURDIR)/bin/host-tool \
					find ./ -type d -not -path "web/sites/default/files*" -exec chmod g+s {} \;
	$(CURDIR)/bin/host-tool \
					chmod -R u=rwx,g=rwxs,o=rwx ./web/sites/default/files

# ------------------------------------------------------------------------------
# DOCKER
# ------------------------------------------------------------------------------
docker-running:
	@docker inspect -f '{{.State.Running}}' mobomo/mobomou-{db,php,web,memcached} &>/dev/null \
					|| (echo "Containers are not running" && exit 1)

docker-rebuild:
	docker-compose -f ${DOCKER_COMPOSE_FILE} up -d --build
	docker-compose -f ${DOCKER_COMPOSE_FILE} ps

docker-status:
	docker-compose -f ${DOCKER_COMPOSE_FILE} ps

docker-start:
	docker-compose -f ${DOCKER_COMPOSE_FILE} up -d
	docker-compose -f ${DOCKER_COMPOSE_FILE} ps

docker-stop:
	docker-compose -f ${DOCKER_COMPOSE_FILE} down

docker-restart: docker-stop docker-start

docker-destroy:
	docker-compose -f ${DOCKER_COMPOSE_FILE} down -v

# ------------------------------------------------------------------------------
# COMPOSER
# ------------------------------------------------------------------------------
composer-install:
	$(CURDIR)/bin/composer install \
					--ignore-platform-reqs \
					--no-interaction \
					--no-progress

composer-update:
	$(CURDIR)/bin/composer update \
					--ignore-platform-reqs

composer-update-lock:
	$(CURDIR)/bin/composer update \
					--lock

# ------------------------------------------------------------------------------
# DRUPAL
# ------------------------------------------------------------------------------
drupal-init: drupal-preserve-config drupal-install drupal-restore-preserved-config drupal-cache-clear
drupal-install :
	$(CURDIR)/bin/drush \
					site:install opigno_lms \
					--yes \
					--account-name=admin \
					--account-pass=admin \
#									-vvv \
#									--existing-config \
#									install_configure_form.enable_update_status_module=NULL \
#									install_configure_form.enable_update_status_emails=NULL
	$(CURDIR)/bin/tool chmod 777 /var/www/web/sites/default/files

drupal-cache-clear:
	$(CURDIR)/bin/drush cache:rebuild

# Update Drupal core
drupal-upgrade:
	$(CURDIR)/bin/composer update drupal/core \
					--with-all-dependencies \
					--ignore-platform-reqs

drupal-updb:
	$(CURDIR)/bin/drush updatedb --yes

drupal-config-init: docker-running
	@if [ -e ./config/system.site.yml ]; then \
					echo "Config found. Processing setting uuid..."; \
					cat ./config/system.site.yml | \
					grep uuid | tail -c +7 | head -c 36 | \
					$(CURDIR)/bin/drush config:set -y system.site uuid - ; \
	else \
					echo "Config is empty. Skipping uuid init..."; \
	fi;

# preserve-config and restore-preserve-config are an attempt to avoid the
# problem of drush site:install being unable to run when set to install a
# profile containing a hook_install() instance. Great sentence.
drupal-preserve-config:
	$(CURDIR)/bin/host-tool \
					cp -r config tmpconfig

drupal-restore-preserved-config:
	$(CURDIR)/bin/host-tool \
					rm -rf config; \
					mv tmpconfig config;

drupal-config-import: docker-running
	@if [ -e ./config/system.site.yml ]; then \
					echo "Config found. Importing config..."; \
					$(CURDIR)/bin/drush config:import --yes ; \
					$(CURDIR)/bin/drush config:import --yes ; \
	else
					echo "Config is empty. Skipping import..."; \
	fi;

drupal-config-export: docker-running
	$(CURDIR)/bin/drush config:export --yes

drupal-config-validate: docker-running
	$(CURDIR)/bin/drush config:status

drupal-config-refresh: drupal-config-init drupal-config-import

drupal-files-purge:
	$(CURDIR)/bin/host-tool \
					rm -rf web/sites/default/files/*
