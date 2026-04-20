default:
    @just --list

format:
    nix fmt -- --ci
    stylua --check .
    prettier --check .

lint:
    git ls-files '*.lua' | xargs selene --display-style quiet
    lua-language-server --check . --checklevel=Warning
    vimdoc-language-server check doc/ --no-runtime-tags

ci: format lint
    @:
