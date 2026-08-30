# ai-modules Makefile.
#
# Targets:
#   make deploy / global / install   deploy artefacts to global config dirs
#   make uninstall                   remove previously deployed artefacts
#   make clean                       remove managed deployment backups
#   make lint                        report lint issues across md/json/sh
#   make fix                         auto-fix lint issues where possible
#   make help                        list targets
#
# Tooling required for lint/fix: markdownlint-cli, jq, shellcheck.

.DEFAULT_GOAL := help

# File discovery — evaluated once at parse time. Excludes .git, deployment
# backup directories, and every regenerated subtree under `tests/` (committed
# lint should not scan transient sandboxes). The authored harness under
# `tests/` is committed, so it IS linted; the prunes below mirror
# `tests/.gitignore`, and the two lists are changed together.
EXCLUDE     := -path ./.git -prune -o \
               -path './deployment/.deploy-backup-*' -prune -o \
               -name workspace -prune -o \
               -name scratch -prune -o \
               -name .eval_cache -prune -o \
               -name __pycache__ -prune -o \
               -path './tests/wiki/layer2/AS-*' -prune -o \
               -path './tests/wiki/layer2/L2-*' -prune -o \
               -path './tests/wiki/layer2/WI-*' -prune -o \
               -path './tests/wiki/layer2/WU-*' -prune -o \
               -path './tests/trigger_evals/results/*' -prune -o \
               -path '*/results/run-*' -prune -o
MD_FILES    := $(shell find . $(EXCLUDE) -type f -name '*.md' -print)
JSON_FILES  := $(shell find . $(EXCLUDE) -type f -name '*.json' -print)
SH_FILES    := $(shell find . $(EXCLUDE) -type f -name '*.sh' -print)

.PHONY: help \
        deploy global install uninstall clean \
        lint lint-md lint-json lint-sh \
        fix fix-md

help: ## Show this help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z][a-zA-Z_-]*:.*?## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

deploy: ## Deploy artefacts to global config dirs (--global).
	./deployment/deployment.sh --global

global: deploy   ## Alias for `make deploy`.
install: deploy  ## Alias for `make deploy`.

uninstall: ## Remove previously deployed artefacts (--uninstall).
	./deployment/deployment.sh --uninstall

clean: ## Remove managed deployment backups (--clear-backups).
	./deployment/deployment.sh --clear-backups

lint: ## Run all linters and report issues across md/json/sh.
	@rc=0; \
	$(MAKE) --no-print-directory lint-md   || rc=1; \
	$(MAKE) --no-print-directory lint-json || rc=1; \
	$(MAKE) --no-print-directory lint-sh   || rc=1; \
	exit $$rc

lint-md:
	@printf '\n== markdown ($(words $(MD_FILES)) files) ==\n'
	@markdownlint $(MD_FILES)

lint-json:
	@printf '\n== json ($(words $(JSON_FILES)) files) ==\n'
	@for f in $(JSON_FILES); do jq empty "$$f" || exit 1; done && echo "ok"

lint-sh:
	@printf '\n== shell ($(words $(SH_FILES)) files) ==\n'
	@shellcheck $(SH_FILES)

fix: fix-md ## Auto-fix lint issues where possible (markdown only).
	@echo
	@echo "json: syntax-only check, nothing to auto-fix"
	@echo "shell: shellcheck has no auto-fix; review and edit manually"

fix-md:
	@printf '\n== markdown --fix ($(words $(MD_FILES)) files) ==\n'
	@markdownlint --fix $(MD_FILES)
