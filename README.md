# AstroNvim Template

**NOTE:** This is for AstroNvim v6+

A template for getting started with [AstroNvim](https://github.com/AstroNvim/AstroNvim)

## Local documentation

- [Neovim keybindings guide (简体中文)](docs/neovim-keybindings-guide.md): entry-point quick reference, detailed common and less-common keys grouped by entry, mode differences, safety notes, and complete workflows at the end.
- [C++/Rust and CMake development](LOCAL-DEVELOPMENT.txt)
- [Markdown rendering](LOCAL-MARKDOWN.txt)

The keybindings guide describes this Neovim configuration using standard key names such as Ctrl and Esc. Check the notation and mode before using a shortcut.

## 🛠️ Installation

#### Make a backup of your current nvim and shared folder

```shell
mv ~/.config/nvim ~/.config/nvim.bak
mv ~/.local/share/nvim ~/.local/share/nvim.bak
mv ~/.local/state/nvim ~/.local/state/nvim.bak
mv ~/.cache/nvim ~/.cache/nvim.bak
```

#### Create a new user repository from this template

Press the "Use this template" button above to create a new repository to store your user configuration.

You can also just clone this repository directly if you do not want to track your user configuration in GitHub.

#### Clone the repository

```shell
git clone https://github.com/<your_user>/<your_repository> ~/.config/nvim
```

#### Start Neovim

```shell
nvim
```
