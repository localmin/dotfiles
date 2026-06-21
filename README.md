# dotfiles

Setting up the development environment on macOS. 

## Usage

After downloading the necessary applications(brew, curl etc...), run the following commands in order

``` sh
./dotfilesLink.sh   # symlink shell/editor configs and Claude Code settings
brew bundle         # install packages from Brewfile
./install.sh        # download standalone apps
./coding-agents/install.sh     # link CLAUDE.md/skills/MCP, fetch vendored skills, install LSP servers
```

`./coding-agents/install.sh` also fetches the vendored external skills pinned in `coding-agents/vendor/manifest.tsv`
(their payload is gitignored), so a fresh machine gets them as part of setup.
