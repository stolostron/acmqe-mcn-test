SHELL := /bin/bash
RUNTIME ?= docker
SUBM_CONTAINER_NAME ?= subm-qe
SUBM_CONTAINER_IMAGE ?= quay.io/maxbab/subm-test:latest
export RUNTIME
export SUBM_CONTAINER_NAME
export SUBM_CONTAINER_IMAGE
export ENV_CONF

SUBM_PLATFORM ?= aws,gcp
SUBM_GLOBALNET ?= true
SUBM_DOWNSTREAM ?= true
SUBM_GW_RANDOM ?= false
export SUBM_PLATFORM
export SUBM_GLOBALNET
export SUBM_DOWNSTREAM
export OC_CLUSTER_API
export OC_CLUSTER_USER
export OC_CLUSTER_PASS

.DEFAULT: help

.PHONY: env-deploy env-destroy submariner-deploy submariner-test deploy-local-env destroy-local-env

help:
	@echo "ACM environment with Submariner deployment/test from local container"
	@echo ""
	@echo "Options:"
	@fgrep -h "##" $(MAKEFILE_LIST) | sed -e 's/\(\:.*\#\#\)/\:\ /' | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'


check-config:
ifeq ($(CONF),)
	$(error The CONF need to be defined for environment creation - "make <target> CONF=value")
else
	@echo "Config file has been provided - $(CONF)"
endif

check-subm-env:
ifeq ($(OC_CLUSTER_API),)
	$(error Missing required environment vars - OC_CLUSTER_API, OC_CLUSTER_USER, OC_CLUSTER_PASS - "make submariner-.. OC_CLUSTER_API=value...")
endif
ifeq ($(OC_CLUSTER_USER),)
	$(error Missing required environment vars - OC_CLUSTER_API, OC_CLUSTER_USER, OC_CLUSTER_PASS - "make submariner-.. OC_CLUSTER_API=value...")
endif
ifeq ($(OC_CLUSTER_PASS),)
	$(error Missing required environment vars - OC_CLUSTER_API, OC_CLUSTER_USER, OC_CLUSTER_PASS - "make submariner-.. OC_CLUSTER_API=value...")
endif


env-deploy: check-config deploy-local-env ##Deploy ACM based environment with managed clusters
	$(RUNTIME) exec \
		-e OC_CLUSTER_API=$(OC_CLUSTER_API) -e OC_CLUSTER_USER=$(OC_CLUSTER_USER) -e OC_CLUSTER_PASS=$(OC_CLUSTER_PASS) \
		-it $(SUBM_CONTAINER_NAME) \
		ansible-playbook -v playbooks/env_deploy.yml -e @"$(CONF)" -e state=present

env-destroy: check-config deploy-local-env ##Destroy ACM based environment with managed clusters
	$(RUNTIME) exec \
		-e OC_CLUSTER_API=$(OC_CLUSTER_API) -e OC_CLUSTER_USER=$(OC_CLUSTER_USER) -e OC_CLUSTER_PASS=$(OC_CLUSTER_PASS) \
		-it $(SUBM_CONTAINER_NAME) \
		ansible-playbook -v playbooks/env_destroy.yml -e @"$(CONF)" -e state=absent
	$(MAKE) destroy-local-env

submariner-deploy: check-subm-env deploy-local-env ##Deploy Submariner on ACM based environment
	$(RUNTIME) exec \
		-e OC_CLUSTER_API=$(OC_CLUSTER_API) -e OC_CLUSTER_USER=$(OC_CLUSTER_USER) -e OC_CLUSTER_PASS=$(OC_CLUSTER_PASS) \
		-it $(SUBM_CONTAINER_NAME) \
		./run.sh --deploy --platform "$(SUBM_PLATFORM)" \
		--globalnet "$(SUBM_GLOBALNET)" --downstream "$(SUBM_DOWNSTREAM)" --subm-gateway-random "$(SUBM_GW_RANDOM)"

submariner-test: check-subm-env deploy-local-env ##Test Submariner on ACM based environment
	$(RUNTIME) exec \
		-e OC_CLUSTER_API=$(OC_CLUSTER_API) -e OC_CLUSTER_USER=$(OC_CLUSTER_USER) -e OC_CLUSTER_PASS=$(OC_CLUSTER_PASS) \
		-it $(SUBM_CONTAINER_NAME) \
		./run.sh --test --platform "$(SUBM_PLATFORM)" --downstream "$(SUBM_DOWNSTREAM)"

deploy-local-env: ##Deploy container for environment deployment
	scripts/local_environment.sh --deploy --runtime "$(RUNTIME)"

destroy-local-env: ##Destroy container for environment deployment
	scripts/local_environment.sh --destroy --runtime "$(RUNTIME)"
