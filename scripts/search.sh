#!/bin/bash

rg --files | fzf --preview 'bat --style=numbers --color=always {}' \
  --bind 'enter:execute(nvim {})'
