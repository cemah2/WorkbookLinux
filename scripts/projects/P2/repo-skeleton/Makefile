# Points d'entrée du mono-repo Factura v2
ENV ?= staging
TF  := tofu -chdir=infra
AP  := ansible-playbook -i ansible/inventory/$(ENV).ini

.PHONY: help lint infra-plan infra-apply baseline deploy monitoring \
        backup-test rebuild

help:
	@grep -E '^[a-z-]+:' Makefile | cut -d: -f1 | sort | tr '\n' ' '; echo

lint:
	pre-commit run --all-files

infra-plan:
	$(TF) workspace select $(ENV) && $(TF) plan -var-file=envs/$(ENV).tfvars

infra-apply:
	$(TF) workspace select $(ENV) && \
	  $(TF) apply -auto-approve -var-file=envs/$(ENV).tfvars

baseline:
	$(AP) ansible/playbooks/baseline.yml

deploy:
	$(AP) ansible/playbooks/deploy.yml -e factura_image_tag=$(TAG)

monitoring:
	ansible-playbook -i ansible/inventory/ops.ini \
	  ansible/playbooks/monitoring.yml

rebuild:
	bash tools/rebuild.sh $(ENV) $(TAG)
