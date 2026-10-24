# AstroNvim Template

**NOTE:** This is for AstroNvim v6+

A template for getting started with [AstroNvim](https://github.com/AstroNvim/AstroNvim)

## Local documentation

- [Neovim keybindings guide (简体中文)](docs/neovim-keybindings-guide.md): entry-point quick reference, detailed common and less-common keys grouped by entry, mode differences, safety notes, and complete workflows at the end.
- [C++/Rust and CMake development](LOCAL-DEVELOPMENT.txt)
- [Markdown rendering](LOCAL-MARKDOWN.txt)
- [Typst and in-editor PDF preview](LOCAL-TYPST.txt)

The keybindings guide describes this Neovim configuration using standard key names such as Ctrl and Esc. Check the notation and mode before using a shortcut.

## Typst and in-editor PDF preview

Open a `.typ` source file in Neovim running directly in Kitty, outside Zellij.
Use `Space l f` to format, `Space w` to save, then `:TypstCompile` (or
`:TypstPreview` / `:TypstPdf`) to compile and show the PDF on the right.
Successful recompilation refreshes the existing pane without stealing source
focus; failed compilation keeps the last good preview. In the PDF pane, use
`]p` / `[p` to change page, `r` to reload and `q` to close it.

Requirements: Typst and Tinymist at `~/.local/bin/typst` and
`~/.local/bin/tinymist`, plus ImageMagick and Ghostscript (`magick` and
`/usr/bin/gs`). On Fedora, install the latter with
`sudo dnf install ImageMagick ghostscript`. See [the full setup and usage
notes](LOCAL-TYPST.txt) for versions, main-file selection and the optional
browser preview (`:TypstBrowser`). Tool binaries, generated PDFs, fonts and
preview caches are not included in this configuration repository.

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
