# Android agentic pipeline - convenience entry points.
# Each target is a thin wrapper over the matching skill script, so the Makefile
# and the agent run exactly the same commands.

SHELL := /usr/bin/env bash
ROOT  := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
SKILLS := $(ROOT).agents/skills

.DEFAULT_GOAL := help
.PHONY: help check setup-host doctor bootstrap spec scaffold verify test device device-check release clean-state skills

help: ## Show this help
	@printf '\nAndroid agentic pipeline\n\n'
	@awk 'BEGIN{FS=":.*## "} /^[a-zA-Z_-]+:.*## /{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf '\nG0 intake -> G1 spec -> G2 scaffold -> G3 domain -> G4 ui -> G5 verify -> G6 device -> G7 release\n\n'

check: ## Lint the kit itself (skills, scripts, contracts, CLI usage)
	@$(ROOT)scripts/check_pipeline.sh

setup-host: ## Fix/verify host prerequisites (JDK, KVM, SDK, AVD); run in your own shell
	@$(ROOT)scripts/setup_host.sh

doctor: ## Diagnose the environment (SDK, JDK, CLI, emulator)
	@$(ROOT)scripts/doctor.sh

bootstrap: ## Prepare state dirs, memory files and (optionally) link a project
	@$(ROOT)scripts/bootstrap.sh

spec: ## Show the current spec + state (G1 outputs)
	@cat $(ROOT)app_workspace/.pipeline/STATE.json 2>/dev/null || echo "no STATE.json"
	@echo "---"
	@test -f $(ROOT)app_workspace/.pipeline/spec.json && python3 -m json.tool $(ROOT)app_workspace/.pipeline/spec.json | head -40 || echo "no spec.json yet (run 01-spec-and-scope)"

scaffold: ## G2 - create the Android project with Android CLI and verify it builds
	@$(SKILLS)/02-android-scaffold/scripts/scaffold_project.sh

verify: ## G5 - build + unit tests + lint + preview discovery
	@$(SKILLS)/05-build-test-loop/scripts/verify.sh

test: ## G5 - unit tests only (fast)
	@$(SKILLS)/05-build-test-loop/scripts/verify.sh --only test

device: ## G6 - boot/create an emulator and run the debug app
	@$(SKILLS)/07-device-verification/scripts/device_up.sh

device-check: ## G6 - screenshot + layout + crash check evidence
	@$(SKILLS)/07-device-verification/scripts/device_check.sh

release: ## G7 - release build, lint, R8/size analysis, quality report
	@$(SKILLS)/08-release-and-quality/scripts/quality_gate.sh

skills: ## List pipeline skills and official Android skills available
	@find $(SKILLS) -maxdepth 2 -name SKILL.md | sed 's|$(SKILLS)/||; s|/SKILL.md||' | sort
	@echo "---"
	@command -v android >/dev/null && android skills list 2>/dev/null | head -5 || echo "android CLI not found"

clean-state: ## Remove pipeline evidence (keeps sources); asks first
	@printf 'Delete app_workspace/.pipeline/reports and artifacts? [y/N] '; read -r a; \
	case "$$a" in y|Y) rm -rf $(ROOT)app_workspace/.pipeline/reports $(ROOT)app_workspace/.pipeline/artifacts; echo "removed" ;; *) echo "aborted" ;; esac
