-- ~/.config/nvim/init.lua
-- Starter config: sane defaults + a few keymaps. NO plugins yet.
-- This is the foundation ThePrimeagen's "0 to LSP" video builds on top of.
--
-- Heads-up before you watch it (see README "Neovim notes"): that video uses
-- Packer (now unmaintained) and predates Neovim 0.11/0.12's new built-in LSP
-- and plugin-manager APIs. The *ideas* all transfer; the plugin-manager and
-- LSP syntax have moved on (lazy.nvim is the current standard).

-- Leader must be set BEFORE anything that references <leader>.
vim.g.mapleader = " "
vim.g.maplocalleader = " "

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------
local opt = vim.opt

opt.number = true
opt.relativenumber = true          -- relative numbers make j/k motions fast

opt.mouse = "a"
opt.clipboard = ""                 -- keep yanks local by default (OSC52 below)

-- Indentation: 4 spaces, Python-friendly
opt.expandtab = true
opt.tabstop = 4
opt.shiftwidth = 4
opt.softtabstop = 4
opt.smartindent = true
opt.autoindent = true

opt.wrap = false

-- Searching
opt.ignorecase = true
opt.smartcase = true               -- case-sensitive only when you type a capital
opt.hlsearch = false
opt.incsearch = true

-- UI
opt.termguicolors = true           -- 24-bit color (works via Ghostty + tmux)
opt.signcolumn = "yes"             -- stable gutter; text doesn't jump
opt.scrolloff = 8
opt.cursorline = true
opt.splitright = true
opt.splitbelow = true

-- Files: persistent undo (stored on the mounted state volume), no swap/backup
opt.undofile = true
opt.swapfile = false
opt.backup = false

opt.updatetime = 250
opt.timeoutlen = 400

--------------------------------------------------------------------------------
-- System clipboard over OSC 52
-- Lets yanks reach your HOST clipboard through tmux + Ghostty, even though
-- you're inside a container. Copy is widely supported; paste from the host
-- needs Ghostty's `clipboard-read = allow` (see README).
--------------------------------------------------------------------------------
local osc52 = require("vim.ui.clipboard.osc52")
vim.g.clipboard = {
  name = "OSC52",
  copy  = { ["+"] = osc52.copy("+"),  ["*"] = osc52.copy("*") },
  paste = { ["+"] = osc52.paste("+"), ["*"] = osc52.paste("*") },
}

--------------------------------------------------------------------------------
-- Keymaps
--------------------------------------------------------------------------------
local map = vim.keymap.set

map("n", "<Esc>", "<cmd>nohlsearch<CR>")                 -- clear search highlight
map("n", "<leader>w", "<cmd>write<CR>", { desc = "Save" })
map("n", "<leader>q", "<cmd>quit<CR>",  { desc = "Quit" })

-- Explicit SYSTEM-clipboard yank/paste
map({ "n", "v" }, "<leader>y", [["+y]], { desc = "Yank to system clipboard" })
map({ "n", "v" }, "<leader>p", [["+p]], { desc = "Paste from system clipboard" })

-- Window navigation
map("n", "<C-h>", "<C-w>h")
map("n", "<C-j>", "<C-w>j")
map("n", "<C-k>", "<C-w>k")
map("n", "<C-l>", "<C-w>l")

-- Move selected lines up/down and re-indent
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Keep the cursor centered on half-page jumps and search results
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")

--------------------------------------------------------------------------------
-- Plugins & LSP go BELOW here.
-- The video will have you install a plugin manager, then Telescope, Treesitter,
-- LSP, and completion. Current path: lazy.nvim (not Packer). As this grows,
-- split it into lua/<you>/ modules and `require` them from this file.
--------------------------------------------------------------------------------
