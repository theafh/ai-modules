# ai-modules Makefile.
#
# Targets:
#   make deploy / global             deploy artefacts to global config dirs
#   make install                     prepare the environment: report the declared tool floor (toolchain.conf)
#   make update                      redeploy every scope the deploy log records, from this checkout
#   make uninstall                   remove previously deployed artefacts; a scope flag limits it to that scope, a scopeless run covers every scope
#   make clean                       remove managed deployment backups
#   make test                        run every deterministic test surface
#   make plugin-test                 run the OpenCode plugin unit tests and typecheck
#   make lint                        report lint issues across md/json/sh/frontmatter
#   make fix                         auto-fix lint issues where possible
#   make help                        list targets
#
# Tooling: `make install` reports the declared floor from toolchain.conf.
# Python 3 is an accepted standing dependency for helper scripts.
# Tooling required for plugin-test: bun.

.DEFAULT_GOAL := help

# Declared tool floor read by `make install` (name|detect|minimum|macos|linux).
TOOLCHAIN := toolchain.conf

# File discovery — evaluated once at parse time. Excludes .git, deployment
# backup directories, and every regenerated subtree under `tests/` (committed
# lint should not scan transient sandboxes). The authored harness under
# `tests/` is committed, so it IS linted; the prunes below mirror
# `tests/.gitignore`, and the two lists are changed together. Two
# run-directory prunes cover directories that keep their own `.gitignore`
# holding `*`, so they stay out of git scope and out of lint scope alike:
# `.agent_spinner`, the agent_spinner run directory, and the shipped
# `.git_auto_review` review-and-fix run. The `.git_auto_review` prune covers a
# review-and-fix run this repo leaves in its own root: its
# `.git_auto_review/.gitignore` holds `*`, so that run directory stays out of
# git scope and out of lint scope alike, sitting beside the `tests/.gitignore`
# mirror the other prunes follow. `.agent_spinner` follows the same model.
EXCLUDE     := -path ./.git -prune -o \
               -name node_modules -prune -o \
               -path './deployment/.deploy-backup-*' -prune -o \
               -name workspace -prune -o \
               -name scratch -prune -o \
               -name .eval_cache -prune -o \
               -name .vendor_probe -prune -o \
               -name __pycache__ -prune -o \
               -name .agent_spinner -prune -o \
               -name .git_auto_review -prune -o \
               -path './tests/wiki/layer2/AS-*' -prune -o \
               -path './tests/wiki/layer2/L2-*' -prune -o \
               -path './tests/wiki/layer2/WI-*' -prune -o \
               -path './tests/wiki/layer2/WU-*' -prune -o \
               -path './tests/wiki/layer2/MP-*' -prune -o \
               -path './tests/trigger_evals/results/*/*' -prune -o \
               -path '*/results/run-*' -prune -o
MD_FILES    := $(shell find . $(EXCLUDE) -type f -name '*.md' -print)
JSON_FILES  := $(shell find . $(EXCLUDE) -type f -name '*.json' -print)
SH_FILES    := $(shell find . $(EXCLUDE) -type f -name '*.sh' -print)

.PHONY: help \
        deploy global install update uninstall clean \
        test plugin-test \
        lint lint-md lint-json lint-sh lint-frontmatter \
        fix fix-md

help: ## Show this help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z][a-zA-Z_-]*:.*?## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

deploy: ## Deploy artefacts to global config dirs (--global).
	./deployment/deployment.sh --global

global: deploy   ## Alias for `make deploy`.

install: ## Prepare the environment: report the declared tool floor (toolchain.conf).
	@status=0; \
	platform=$$(uname -s 2>/dev/null || echo unknown); \
	case "$$platform" in \
	  Darwin) field=4 ;; \
	  Linux)  field=5 ;; \
	  *)      field=0 ;; \
	esac; \
	printf 'ai-modules toolchain floor (%s)\n\n' "$$platform"; \
	while IFS='|' read -r name detect minimum macos linux; do \
	  case "$$name" in ''|'#'*) continue ;; esac; \
	  if [ "$$field" -eq 4 ]; then install_cmd=$$macos; \
	  elif [ "$$field" -eq 5 ]; then install_cmd=$$linux; \
	  else install_cmd=; fi; \
	  problem=; \
	  if ! command -v "$$name" >/dev/null 2>&1; then \
	    printf '  %-14s missing\n' "$$name"; \
	    status=1; problem=missing; \
	  elif [ -n "$$minimum" ]; then \
	    found=$$($$detect 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1); \
	    if [ -z "$$found" ]; then \
	      printf '  %-14s version unknown (could not read one from `%s`)\n' "$$name" "$$detect"; \
	      status=1; problem=unknown; \
	    else \
	      lowest=$$(printf '%s\n%s\n' "$$minimum" "$$found" | sort -V | head -n 1); \
	      if [ "$$lowest" != "$$minimum" ]; then \
	        printf '  %-14s below minimum (found %s, need %s)\n' "$$name" "$$found" "$$minimum"; \
	        status=1; problem=old; \
	      else \
	        printf '  %-14s satisfied (%s >= %s)\n' "$$name" "$$found" "$$minimum"; \
	      fi; \
	    fi; \
	  else \
	    printf '  %-14s satisfied\n' "$$name"; \
	  fi; \
	  if [ -n "$$problem" ]; then \
	    if [ -z "$$install_cmd" ]; then \
	      printf '      no install command for %s; install %s manually\n' "$$platform" "$$name"; \
	    else \
	      manager=$${install_cmd%% *}; \
	      if [ "$$manager" = sudo ]; then \
	        manager=$${install_cmd#sudo }; manager=$${manager%% *}; \
	      fi; \
	      if command -v "$$manager" >/dev/null 2>&1; then \
	        printf '      install: %s\n' "$$install_cmd"; \
	      else \
	        printf '      install: package manager `%s` is not installed; install %s, then re-run make install\n' "$$manager" "$$manager"; \
	      fi; \
	    fi; \
	  fi; \
	done < $(TOOLCHAIN); \
	printf '\n'; \
	if [ "$$status" -ne 0 ]; then \
	  printf 'Tool floor not satisfied.\n'; \
	else \
	  printf 'Every declared tool is satisfied.\n'; \
	fi; \
	exit $$status

update: ## Redeploy every scope the deploy log records, from this checkout (--update).
	./deployment/deployment.sh --update

uninstall: ## Remove previously deployed artefacts; a scope flag limits it to that scope, a scopeless run covers every scope (--uninstall).
	./deployment/deployment.sh --uninstall

clean: ## Remove managed deployment backups (--clear-backups).
	./deployment/deployment.sh --clear-backups

test: ## Run every deterministic test surface (tests/run_all.sh).
	bash tests/run_all.sh

plugin-test: ## Run the OpenCode plugin unit tests and typecheck (bun).
	cd harness-plugins/opencode_v2 && bun install --frozen-lockfile && bun run test && bun run typecheck

lint: ## Run all linters and report issues across md/json/sh/frontmatter (Python 3).
	@rc=0; \
	$(MAKE) --no-print-directory lint-md           || rc=1; \
	$(MAKE) --no-print-directory lint-json         || rc=1; \
	$(MAKE) --no-print-directory lint-sh           || rc=1; \
	$(MAKE) --no-print-directory lint-frontmatter  || rc=1; \
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

# Every tracked .md/.mdc outside tests/ that opens with `---` is checked
# against a strict YAML subset, and skill_doctor's discovery_safety.py runs in
# place over every tracked SKILL.md. Python 3 is the only dependency.
lint-frontmatter:
	@python3 scripts/lint_frontmatter.py

fix: fix-md ## Auto-fix lint issues where possible (markdown only).
	@echo
	@echo "json: syntax-only check, nothing to auto-fix"
	@echo "shell: shellcheck has no auto-fix; review and edit manually"

fix-md:
	@printf '\n== markdown --fix ($(words $(MD_FILES)) files) ==\n'
	@markdownlint --fix $(MD_FILES)
