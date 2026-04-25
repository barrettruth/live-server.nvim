default:
    @just --list

format:
    nix fmt -- --ci
    stylua --check .
    biome format .

lint:
    git ls-files '*.lua' | xargs selene --display-style quiet
    lua-language-server --check . --checklevel=Warning
    vimdoc-language-server check doc/

ci: format lint
    @:
