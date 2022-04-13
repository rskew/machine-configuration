set -gx PATH $HOME/scripts $PATH
set -gx PATH $HOME/bin $PATH

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
