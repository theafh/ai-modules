# ai-modules Makefile.
#
# Targets:
#   make deploy / global / install   deploy artefacts to global config dirs
#   make uninstall                   remove previously deployed artefacts; a scope flag limits it to that scope, a scopeless run covers every scope
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
               -name .vendor_probe -prune -o \
               -name __pycache__ -prune -o \
               -path './tests/wiki/layer2/AS-*' -prune -o \
               -path './tests/wiki/layer2/L2-*' -prune -o \
               -path './tests/wiki/layer2/WI-*' -prune -o \
               -path './tests/wiki/layer2/WU-*' -prune -o \
               -path './tests/wiki/layer2/MP-*' -prune -o \
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

uninstall: ## Remove previously deployed artefacts; a scope flag limits it to that scope, a scopeless run covers every scope (--uninstall).
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

# Bash 3.2 floor scanned by lint-sh over SH_FILES. The recipe names each
# greppable token: declare -A, ${var^^}, ${var,,}, mapfile, readarray,
# declare -n, wait -n, read -N, shopt -s globstar, ${var@Q}, &>>, ;;&,
# coproc, [[ -v, EPOCHSECONDS, printf '%(fmt)T'.
lint-sh:
	@printf '\n== shell ($(words $(SH_FILES)) files) ==\n'
	@# declare -A ${var^^} ${var,,} mapfile readarray declare -n wait -n read -N shopt -s globstar ${var@Q} &>> ;;& coproc [[ -v EPOCHSECONDS printf '%(fmt)T'
	@rc=0; \
	shellcheck $(SH_FILES) || rc=1; \
	status=0; \
	floor_hit() { \
	  label="$$1"; pattern="$$2"; \
	  for f in $(SH_FILES); do \
	    if grep -nE -H -e "$$pattern" "$$f" >/dev/null 2>&1; then \
	      printf 'bash 3.2 floor: %s: %s\n' "$$f" "$$label"; \
	      grep -nE -H -e "$$pattern" "$$f"; \
	      status=1; \
	    fi; \
	  done; \
	}; \
	floor_hit 'declare -A' 'declare -A'; \
	floor_hit '$${var^^}' '\$\{[^}]*\^\^'; \
	floor_hit '$${var,,}' '\$\{[^}]*,,'; \
	floor_hit 'mapfile' '(^|[^[:alnum:]_])mapfile([^[:alnum:]_]|$$)'; \
	floor_hit 'readarray' '(^|[^[:alnum:]_])readarray([^[:alnum:]_]|$$)'; \
	floor_hit 'declare -n' 'declare -n([[:space:]]|$$)'; \
	floor_hit 'wait -n' 'wait -n([[:space:]]|$$)'; \
	floor_hit 'read -N' 'read -N([[:space:]]|$$)'; \
	floor_hit 'shopt -s globstar' 'shopt[[:space:]]+-s[[:space:]].*globstar'; \
	floor_hit '$${var@Q}' '\$\{[^}]*@Q'; \
	floor_hit '&>>' '&>>'; \
	floor_hit ';;&' ';;&'; \
	floor_hit 'coproc' '(^|[^[:alnum:]_])coproc([^[:alnum:]_]|$$)'; \
	floor_hit '[[ -v' '\[\[[[:space:]]+-v([[:space:]]|$$)'; \
	floor_hit 'EPOCHSECONDS' '(^|[^[:alnum:]_])EPOCHSECONDS([^[:alnum:]_]|$$)'; \
	floor_hit "printf '%(fmt)T'" '%[(][^)]*[)]T'; \
	[ "$$status" -eq 0 ] || rc=1; \
	exit $$rc

fix: fix-md ## Auto-fix lint issues where possible (markdown only).
	@echo
	@echo "json: syntax-only check, nothing to auto-fix"
	@echo "shell: shellcheck has no auto-fix; review and edit manually"

fix-md:
	@printf '\n== markdown --fix ($(words $(MD_FILES)) files) ==\n'
	@markdownlint --fix $(MD_FILES)
