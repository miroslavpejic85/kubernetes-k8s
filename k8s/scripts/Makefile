VERSION=$$(grep version: miro/Chart.yaml | sed -e 's/.*: *//g')
NAMESPACE=miro #$$(./detect_ns.sh)

help: ## Show this help
	@IFS=$$'\n' ; \
		help_lines=(`fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//'`); \
		for help_line in $${help_lines[@]}; do \
				IFS=$$'#' ; \
				help_split=($$help_line) ; \
				help_command=`echo $${help_split[0]} | sed -e 's/^ *//' -e 's/ *$$//'` ; \
				help_info=`echo $${help_split[2]} | sed -e 's/^ *//' -e 's/ *$$//'` ; \
				printf "%-30s %s\n" $$help_command $$help_info ; \
		done

.PHONY: clean
clean: ## Clean the working directory removing the packages and the rendered templates
	rm -fr miro-$(VERSION)*.tgz miro-$(VERSION)*.yaml tmp.*

.PHONY: package
package: ## Create the miro helm package
	helm package miro

.PHONY: template
template: ## Render the miro helm chart template
	helm template miro/ --namespace $(NAMESPACE) -f miro/values.yaml > miro-$(VERSION).yaml

.PHONY: apply
apply: ## Apply the current rendered template
	kubectl apply -f miro-$(VERSION).yaml

.PHONY: delete
delete: ## Delete the current deployment
	kubectl delete -f miro-$(VERSION).yaml