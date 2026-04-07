# vim:ft=zsh
#
# Exec-string wrapper for zsh login shells. cmux keeps ZDOTDIR pointed at this
# wrapper directory until .zshrc so zsh -i -c can install Ghostty's deferred
# ssh() patch after the user's startup files run.

if (( $+functions[_cmux_source_real_zdotfile] )); then
    {
        _cmux_source_real_zdotfile ".zprofile"
    } always {
        _cmux_restore_wrapper_zdotdir
    }
fi
