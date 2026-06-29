.PHONY: test lint install-hooks

test:
	./tests/run.sh

lint:
	@echo "--- checking for redundant [redraw][/redraw] ---"
	@if grep -rn "\[redraw\]\[/redraw\]" utils/ scenarios/ lua/; then \
		echo "ERROR: redundant [redraw][/redraw] found (remove — [message] and [scroll_to] redraw implicitly)"; \
		exit 1; \
	fi
	@echo "--- wmllint ---"
	@if command -v wmllint >/dev/null 2>&1; then \
		wmllint /usr/share/games/wesnoth/1.18/data .; \
	elif [ -x /usr/share/games/wesnoth/1.18/data/tools/wmllint ]; then \
		/usr/share/games/wesnoth/1.18/data/tools/wmllint --dryrun . 2>&1 | grep -v "DeprecationWarning" | grep -v "passed as positional"; \
	else \
		echo "wmllint not found — install wesnoth-1.18-tools to enable"; \
	fi

install-hooks:
	cp .githooks/pre-commit .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit
	@echo "pre-commit hook installed"
