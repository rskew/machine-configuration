set -gx PATH $HOME/machine-configuration/scripts $PATH
set -gx PATH $HOME/bin $PATH
set -gx EDITOR vim

alias rm='rm -i'

alias cat=bat

alias sl='sl -l'

function fish_user_key_bindings
    for mode in insert default visual
        bind -M $mode \cf forward-char
    end
    for mode in insert default visual
        bind -M $mode \cu up-or-search
    end
end

alias gerp=grep
alias grpe=grep

set fish_greeting ""

fish_vi_key_bindings

function nix-develop
  nix develop $argv --command fish
end

alias nix-stray-roots='nix-store --gc --print-roots | egrep -v "^(/nix/var|/proc/.*|/run/\w+-system|\{memory)"'

abbr lvim 'nix --offline run nixpkgs#lunarvim'

####
#### git aliases from https://gist.github.com/freewind/773c3324b5288ff636af
####

abbr gst 'git status'
abbr gd 'git diff'
abbr gdc 'git diff --cached'
abbr gl 'git pull'
abbr gup 'git pull --rebase'
abbr gp 'git push'

abbr glo 'git log --oneline'

abbr ga 'git add'
abbr gaa 'git add --all'

abbr gc 'git commit -v'
abbr gc! 'git commit -v --amend'
abbr gca 'git commit -v -a'
abbr gca! 'git commit -v -a --amend'
abbr gcmsg 'git commit -m'
abbr gcm 'git commit -m'
abbr gco 'git checkout'

abbr grbom 'git fetch origin master; git rebase origin/master'
abbr grbi 'git rebase -i'
abbr grbc 'git rebase --continue'
abbr grba 'git rebase --abort'
