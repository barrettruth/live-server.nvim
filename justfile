default:
    @just --list

format:
    nix fmt -- --ci
    stylua --check .
    vimdoc-language-server format --check doc/
    biome format .

lint:
    git ls-files '*.lua' | xargs selene --display-style quiet
    VIMRUNTIME="$(env -u VIMRUNTIME nvim --headless -u NONE -i NONE '+lua io.write(vim.env.VIMRUNTIME)' +qa)" \
        lua-language-server --check . --checklevel=Warning
    vimdoc-language-server check doc/

ci: format lint
    @:
