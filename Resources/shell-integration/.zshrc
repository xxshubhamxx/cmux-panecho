# vim:ft=zsh
#
# Exec-string wrapper for zsh interactive shells. This runs after the user's
# .zshrc so zsh -i -c gets the same post-startup ssh() patching that prompted
# shells receive from Ghostty's deferred init.

if (( $+functions[_cmux_source_real_zdotfile] )); then
    _cmux_source_real_zdotfile ".zshrc"
fi

if (( $+functions[_cmux_use_real_zdotdir] )); then
    _cmux_use_real_zdotdir
fi

# /etc/zshrc used the wrapper ZDOTDIR for exec-string shells. Restore the
# user's history path now that startup-file chaining is complete.
HISTFILE=${ZDOTDIR-$HOME}/.zsh_history

if (( $+functions[_cmux_patch_ghostty_ssh] )); then
    _cmux_patch_ghostty_ssh
fi

builtin unfunction _cmux_use_real_zdotdir _cmux_restore_wrapper_zdotdir _cmux_source_real_zdotfile 2>/dev/null
builtin unset _cmux_real_zdotdir _cmux_real_zdotdir_mode _cmux_wrapper_zdotdir _cmux_use_exec_string_wrapper
