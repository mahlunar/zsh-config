#compdef shuttle

__shuttle_bash_source() {
	alias shopt=':'
	alias _expand=_bash_expand
	alias _complete=_bash_comp
	emulate -L sh
	setopt kshglob noshglob braceexpand
	source "$@"
}
__shuttle_type() {
	# -t is not supported by zsh
	if [ "$1" == "-t" ]; then
		shift
		# fake Bash 4 to disable "complete -o nospace". Instead
		# "compopt +-o nospace" is used in the code to toggle trailing
		# spaces. We don't support that, but leave trailing spaces on
		# all the time
		if [ "$1" = "__shuttle_compopt" ]; then
			echo builtin
			return 0
		fi
	fi
	type "$@"
}
__shuttle_compgen() {
	local completions w
	completions=( $(compgen "$@") ) || return $?
	# filter by given word as prefix
	while [[ "$1" = -* && "$1" != -- ]]; do
		shift
		shift
	done
	if [[ "$1" == -- ]]; then
		shift
	fi
	for w in "${completions[@]}"; do
		if [[ "${w}" = "$1"* ]]; then
			echo "${w}"
		fi
	done
}
__shuttle_compopt() {
	true # don't do anything. Not supported by bashcompinit in zsh
}
__shuttle_ltrim_colon_completions()
{
	if [[ "$1" == *:* && "$COMP_WORDBREAKS" == *:* ]]; then
		# Remove colon-word prefix from COMPREPLY items
		local colon_word=${1%${1##*:}}
		local i=${#COMPREPLY[*]}
		while [[ $((--i)) -ge 0 ]]; do
			COMPREPLY[$i]=${COMPREPLY[$i]#"$colon_word"}
		done
	fi
}
__shuttle_get_comp_words_by_ref() {
	cur="${COMP_WORDS[COMP_CWORD]}"
	prev="${COMP_WORDS[${COMP_CWORD}-1]}"
	words=("${COMP_WORDS[@]}")
	cword=("${COMP_CWORD[@]}")
}
__shuttle_filedir() {
	local RET OLD_IFS w qw
	__shuttle_debug "_filedir $@ cur=$cur"
	if [[ "$1" = \~* ]]; then
		# somehow does not work. Maybe, zsh does not call this at all
		eval echo "$1"
		return 0
	fi
	OLD_IFS="$IFS"
	IFS=$'\n'
	if [ "$1" = "-d" ]; then
		shift
		RET=( $(compgen -d) )
	else
		RET=( $(compgen -f) )
	fi
	IFS="$OLD_IFS"
	IFS="," __shuttle_debug "RET=${RET[@]} len=${#RET[@]}"
	for w in ${RET[@]}; do
		if [[ ! "${w}" = "${cur}"* ]]; then
			continue
		fi
		if eval "[[ \"\${w}\" = *.$1 || -d \"\${w}\" ]]"; then
			qw="$(__shuttle_quote "${w}")"
			if [ -d "${w}" ]; then
				COMPREPLY+=("${qw}/")
			else
				COMPREPLY+=("${qw}")
			fi
		fi
	done
}
__shuttle_quote() {
    if [[ $1 == \'* || $1 == \"* ]]; then
        # Leave out first character
        printf %q "${1:1}"
    else
	printf %q "$1"
    fi
}
autoload -U +X bashcompinit && bashcompinit
# use word boundary patterns for BSD or GNU sed
LWORD='[[:<:]]'
RWORD='[[:>:]]'
if sed --help 2>&1 | grep -q GNU; then
	LWORD='\<'
	RWORD='\>'
fi
__shuttle_convert_bash_to_zsh() {
	sed \
	-e 's/declare -F/whence -w/' \
	-e 's/_get_comp_words_by_ref "\$@"/_get_comp_words_by_ref "\$*"/' \
	-e 's/local \([a-zA-Z0-9_]*\)=/local \1; \1=/' \
	-e 's/flags+=("\(--.*\)=")/flags+=("\1"); two_word_flags+=("\1")/' \
	-e 's/must_have_one_flag+=("\(--.*\)=")/must_have_one_flag+=("\1")/' \
	-e "s/${LWORD}_filedir${RWORD}/__shuttle_filedir/g" \
	-e "s/${LWORD}_get_comp_words_by_ref${RWORD}/__shuttle_get_comp_words_by_ref/g" \
	-e "s/${LWORD}__ltrim_colon_completions${RWORD}/__shuttle_ltrim_colon_completions/g" \
	-e "s/${LWORD}compgen${RWORD}/__shuttle_compgen/g" \
	-e "s/${LWORD}compopt${RWORD}/__shuttle_compopt/g" \
	-e "s/${LWORD}declare${RWORD}/builtin declare/g" \
	-e "s/\\\$(type${RWORD}/\$(__shuttle_type/g" \
	<<'BASH_COMPLETION_EOF'
# bash completion for shuttle                              -*- shell-script -*-

__shuttle_debug()
{
    if [[ -n ${BASH_COMP_DEBUG_FILE} ]]; then
        echo "$*" >> "${BASH_COMP_DEBUG_FILE}"
    fi
}

# Homebrew on Macs have version 1.3 of bash-completion which doesn't include
# _init_completion. This is a very minimal version of that function.
__shuttle_init_completion()
{
    COMPREPLY=()
    _get_comp_words_by_ref "$@" cur prev words cword
}

__shuttle_index_of_word()
{
    local w word=$1
    shift
    index=0
    for w in "$@"; do
        [[ $w = "$word" ]] && return
        index=$((index+1))
    done
    index=-1
}

__shuttle_contains_word()
{
    local w word=$1; shift
    for w in "$@"; do
        [[ $w = "$word" ]] && return
    done
    return 1
}

__shuttle_handle_go_custom_completion()
{
    __shuttle_debug "${FUNCNAME[0]}: cur is ${cur}, words[*] is ${words[*]}, #words[@] is ${#words[@]}"

    local shellCompDirectiveError=1
    local shellCompDirectiveNoSpace=2
    local shellCompDirectiveNoFileComp=4
    local shellCompDirectiveFilterFileExt=8
    local shellCompDirectiveFilterDirs=16

    local out requestComp lastParam lastChar comp directive args

    # Prepare the command to request completions for the program.
    # Calling ${words[0]} instead of directly shuttle allows to handle aliases
    args=("${words[@]:1}")
    requestComp="${words[0]} __completeNoDesc ${args[*]}"

    lastParam=${words[$((${#words[@]}-1))]}
    lastChar=${lastParam:$((${#lastParam}-1)):1}
    __shuttle_debug "${FUNCNAME[0]}: lastParam ${lastParam}, lastChar ${lastChar}"

    if [ -z "${cur}" ] && [ "${lastChar}" != "=" ]; then
        # If the last parameter is complete (there is a space following it)
        # We add an extra empty parameter so we can indicate this to the go method.
        __shuttle_debug "${FUNCNAME[0]}: Adding extra empty parameter"
        requestComp="${requestComp} \"\""
    fi

    __shuttle_debug "${FUNCNAME[0]}: calling ${requestComp}"
    # Use eval to handle any environment variables and such
    out=$(eval "${requestComp}" 2>/dev/null)

    # Extract the directive integer at the very end of the output following a colon (:)
    directive=${out##*:}
    # Remove the directive
    out=${out%:*}
    if [ "${directive}" = "${out}" ]; then
        # There is not directive specified
        directive=0
    fi
    __shuttle_debug "${FUNCNAME[0]}: the completion directive is: ${directive}"
    __shuttle_debug "${FUNCNAME[0]}: the completions are: ${out[*]}"

    if [ $((directive & shellCompDirectiveError)) -ne 0 ]; then
        # Error code.  No completion.
        __shuttle_debug "${FUNCNAME[0]}: received error from custom completion go code"
        return
    else
        if [ $((directive & shellCompDirectiveNoSpace)) -ne 0 ]; then
            if [[ $(type -t compopt) = "builtin" ]]; then
                __shuttle_debug "${FUNCNAME[0]}: activating no space"
                compopt -o nospace
            fi
        fi
        if [ $((directive & shellCompDirectiveNoFileComp)) -ne 0 ]; then
            if [[ $(type -t compopt) = "builtin" ]]; then
                __shuttle_debug "${FUNCNAME[0]}: activating no file completion"
                compopt +o default
            fi
        fi
    fi

    if [ $((directive & shellCompDirectiveFilterFileExt)) -ne 0 ]; then
        # File extension filtering
        local fullFilter filter filteringCmd
        # Do not use quotes around the $out variable or else newline
        # characters will be kept.
        for filter in ${out[*]}; do
            fullFilter+="$filter|"
        done

        filteringCmd="_filedir $fullFilter"
        __shuttle_debug "File filtering command: $filteringCmd"
        $filteringCmd
    elif [ $((directive & shellCompDirectiveFilterDirs)) -ne 0 ]; then
        # File completion for directories only
        local subDir
        # Use printf to strip any trailing newline
        subdir=$(printf "%s" "${out[0]}")
        if [ -n "$subdir" ]; then
            __shuttle_debug "Listing directories in $subdir"
            __shuttle_handle_subdirs_in_dir_flag "$subdir"
        else
            __shuttle_debug "Listing directories in ."
            _filedir -d
        fi
    else
        while IFS='' read -r comp; do
            COMPREPLY+=("$comp")
        done < <(compgen -W "${out[*]}" -- "$cur")
    fi
}

__shuttle_handle_reply()
{
    __shuttle_debug "${FUNCNAME[0]}"
    local comp
    case $cur in
        -*)
            if [[ $(type -t compopt) = "builtin" ]]; then
                compopt -o nospace
            fi
            local allflags
            if [ ${#must_have_one_flag[@]} -ne 0 ]; then
                allflags=("${must_have_one_flag[@]}")
            else
                allflags=("${flags[*]} ${two_word_flags[*]}")
            fi
            while IFS='' read -r comp; do
                COMPREPLY+=("$comp")
            done < <(compgen -W "${allflags[*]}" -- "$cur")
            if [[ $(type -t compopt) = "builtin" ]]; then
                [[ "${COMPREPLY[0]}" == *= ]] || compopt +o nospace
            fi

            # complete after --flag=abc
            if [[ $cur == *=* ]]; then
                if [[ $(type -t compopt) = "builtin" ]]; then
                    compopt +o nospace
                fi

                local index flag
                flag="${cur%=*}"
                __shuttle_index_of_word "${flag}" "${flags_with_completion[@]}"
                COMPREPLY=()
                if [[ ${index} -ge 0 ]]; then
                    PREFIX=""
                    cur="${cur#*=}"
                    ${flags_completion[${index}]}
                    if [ -n "${ZSH_VERSION}" ]; then
                        # zsh completion needs --flag= prefix
                        eval "COMPREPLY=( \"\${COMPREPLY[@]/#/${flag}=}\" )"
                    fi
                fi
            fi
            return 0;
            ;;
    esac

    # check if we are handling a flag with special work handling
    local index
    __shuttle_index_of_word "${prev}" "${flags_with_completion[@]}"
    if [[ ${index} -ge 0 ]]; then
        ${flags_completion[${index}]}
        return
    fi

    # we are parsing a flag and don't have a special handler, no completion
    if [[ ${cur} != "${words[cword]}" ]]; then
        return
    fi

    local completions
    completions=("${commands[@]}")
    if [[ ${#must_have_one_noun[@]} -ne 0 ]]; then
        completions+=("${must_have_one_noun[@]}")
    elif [[ -n "${has_completion_function}" ]]; then
        # if a go completion function is provided, defer to that function
        __shuttle_handle_go_custom_completion
    fi
    if [[ ${#must_have_one_flag[@]} -ne 0 ]]; then
        completions+=("${must_have_one_flag[@]}")
    fi
    while IFS='' read -r comp; do
        COMPREPLY+=("$comp")
    done < <(compgen -W "${completions[*]}" -- "$cur")

    if [[ ${#COMPREPLY[@]} -eq 0 && ${#noun_aliases[@]} -gt 0 && ${#must_have_one_noun[@]} -ne 0 ]]; then
        while IFS='' read -r comp; do
            COMPREPLY+=("$comp")
        done < <(compgen -W "${noun_aliases[*]}" -- "$cur")
    fi

    if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
		if declare -F __shuttle_custom_func >/dev/null; then
			# try command name qualified custom func
			__shuttle_custom_func
		else
			# otherwise fall back to unqualified for compatibility
			declare -F __custom_func >/dev/null && __custom_func
		fi
    fi

    # available in bash-completion >= 2, not always present on macOS
    if declare -F __ltrim_colon_completions >/dev/null; then
        __ltrim_colon_completions "$cur"
    fi

    # If there is only 1 completion and it is a flag with an = it will be completed
    # but we don't want a space after the =
    if [[ "${#COMPREPLY[@]}" -eq "1" ]] && [[ $(type -t compopt) = "builtin" ]] && [[ "${COMPREPLY[0]}" == --*= ]]; then
       compopt -o nospace
    fi
}

# The arguments should be in the form "ext1|ext2|extn"
__shuttle_handle_filename_extension_flag()
{
    local ext="$1"
    _filedir "@(${ext})"
}

__shuttle_handle_subdirs_in_dir_flag()
{
    local dir="$1"
    pushd "${dir}" >/dev/null 2>&1 && _filedir -d && popd >/dev/null 2>&1 || return
}

__shuttle_handle_flag()
{
    __shuttle_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    # if a command required a flag, and we found it, unset must_have_one_flag()
    local flagname=${words[c]}
    local flagvalue
    # if the word contained an =
    if [[ ${words[c]} == *"="* ]]; then
        flagvalue=${flagname#*=} # take in as flagvalue after the =
        flagname=${flagname%=*} # strip everything after the =
        flagname="${flagname}=" # but put the = back
    fi
    __shuttle_debug "${FUNCNAME[0]}: looking for ${flagname}"
    if __shuttle_contains_word "${flagname}" "${must_have_one_flag[@]}"; then
        must_have_one_flag=()
    fi

    # if you set a flag which only applies to this command, don't show subcommands
    if __shuttle_contains_word "${flagname}" "${local_nonpersistent_flags[@]}"; then
      commands=()
    fi

    # keep flag value with flagname as flaghash
    # flaghash variable is an associative array which is only supported in bash > 3.
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        if [ -n "${flagvalue}" ] ; then
            flaghash[${flagname}]=${flagvalue}
        elif [ -n "${words[ $((c+1)) ]}" ] ; then
            flaghash[${flagname}]=${words[ $((c+1)) ]}
        else
            flaghash[${flagname}]="true" # pad "true" for bool flag
        fi
    fi

    # skip the argument to a two word flag
    if [[ ${words[c]} != *"="* ]] && __shuttle_contains_word "${words[c]}" "${two_word_flags[@]}"; then
			  __shuttle_debug "${FUNCNAME[0]}: found a flag ${words[c]}, skip the next argument"
        c=$((c+1))
        # if we are looking for a flags value, don't show commands
        if [[ $c -eq $cword ]]; then
            commands=()
        fi
    fi

    c=$((c+1))

}

__shuttle_handle_noun()
{
    __shuttle_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    if __shuttle_contains_word "${words[c]}" "${must_have_one_noun[@]}"; then
        must_have_one_noun=()
    elif __shuttle_contains_word "${words[c]}" "${noun_aliases[@]}"; then
        must_have_one_noun=()
    fi

    nouns+=("${words[c]}")
    c=$((c+1))
}

__shuttle_handle_command()
{
    __shuttle_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    local next_command
    if [[ -n ${last_command} ]]; then
        next_command="_${last_command}_${words[c]//:/__}"
    else
        if [[ $c -eq 0 ]]; then
            next_command="_shuttle_root_command"
        else
            next_command="_${words[c]//:/__}"
        fi
    fi
    c=$((c+1))
    __shuttle_debug "${FUNCNAME[0]}: looking for ${next_command}"
    declare -F "$next_command" >/dev/null && $next_command
}

__shuttle_handle_word()
{
    if [[ $c -ge $cword ]]; then
        __shuttle_handle_reply
        return
    fi
    __shuttle_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"
    if [[ "${words[c]}" == -* ]]; then
        __shuttle_handle_flag
    elif __shuttle_contains_word "${words[c]}" "${commands[@]}"; then
        __shuttle_handle_command
    elif [[ $c -eq 0 ]]; then
        __shuttle_handle_command
    elif __shuttle_contains_word "${words[c]}" "${command_aliases[@]}"; then
        # aliashash variable is an associative array which is only supported in bash > 3.
        if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
            words[c]=${aliashash[${words[c]}]}
            __shuttle_handle_command
        else
            __shuttle_handle_noun
        fi
    else
        __shuttle_handle_noun
    fi
    __shuttle_handle_word
}


__shuttle_run_script_args() {
	local cur prev args_output args
	COMPREPLY=()
	cur="${COMP_WORDS[COMP_CWORD]}"
	prev="${COMP_WORDS[COMP_CWORD-1]}"

	template=$'{{ range $i, $arg := .Args }}{{ $arg.Name }}\n{{ end }}'
	if args_output=$(shuttle --skip-pull run "$1" --help --template "$template" 2>/dev/null); then
		args=($(echo "${args_output}"))
		COMPREPLY=( $( compgen -W "${args[*]}" -- "$cur" ) )
		compopt -o nospace
	fi
}

# find available scripts to run
__shuttle_run_scripts() {
	local cur prev scripts currentScript
	COMPREPLY=()
	cur="${COMP_WORDS[COMP_CWORD]}"
	prev="${COMP_WORDS[COMP_CWORD-1]}"
	currentScript="${COMP_WORDS[2]}"

	if [[ ! "${prev}" = "run" ]]; then
		__shuttle_run_script_args $currentScript
		return 0
	fi

	template=$'{{ range $name, $script := .Scripts }}{{ $name }}\n{{ end }}'
	if scripts_output=$(shuttle --skip-pull ls --template "$template" 2>/dev/null); then
		scripts=($(echo "${scripts_output}"))
		COMPREPLY=( $( compgen -W "${scripts[*]}" -- "$cur" ) )
	fi
	return 0
}

# called when the build in completion fails to match
__shuttle_custom_func() {
  case ${last_command} in
      shuttle_run)
          __shuttle_run_scripts
          return
          ;;
      *)
          ;;
  esac
}

_shuttle_completion()
{
    last_command="shuttle_completion"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")
    local_nonpersistent_flags+=("--help")
    local_nonpersistent_flags+=("-h")
    flags+=("--clean")
    flags+=("-c")
    flags+=("--plan=")
    two_word_flags+=("--plan")
    flags+=("--project=")
    two_word_flags+=("--project")
    two_word_flags+=("-p")
    flags+=("--skip-pull")
    flags+=("--verbose")
    flags+=("-v")

    must_have_one_flag=()
    must_have_one_noun=()
    must_have_one_noun+=("bash")
    must_have_one_noun+=("zsh")
    noun_aliases=()
}

_shuttle_documentation()
{
    last_command="shuttle_documentation"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--clean")
    flags+=("-c")
    flags+=("--plan=")
    two_word_flags+=("--plan")
    flags+=("--project=")
    two_word_flags+=("--project")
    two_word_flags+=("-p")
    flags+=("--skip-pull")
    flags+=("--verbose")
    flags+=("-v")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_shuttle_get()
{
    last_command="shuttle_get"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--template=")
    two_word_flags+=("--template")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--clean")
    flags+=("-c")
    flags+=("--plan=")
    two_word_flags+=("--plan")
    flags+=("--project=")
    two_word_flags+=("--project")
    two_word_flags+=("-p")
    flags+=("--skip-pull")
    flags+=("--verbose")
    flags+=("-v")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_shuttle_git-plan()
{
    last_command="shuttle_git-plan"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--clean")
    flags+=("-c")
    flags+=("--plan=")
    two_word_flags+=("--plan")
    flags+=("--project=")
    two_word_flags+=("--project")
    two_word_flags+=("-p")
    flags+=("--skip-pull")
    flags+=("--verbose")
    flags+=("-v")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_shuttle_has()
{
    last_command="shuttle_has"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--script")
    local_nonpersistent_flags+=("--script")
    flags+=("--stdout")
    flags+=("-o")
    local_nonpersistent_flags+=("--stdout")
    local_nonpersistent_flags+=("-o")
    flags+=("--clean")
    flags+=("-c")
    flags+=("--plan=")
    two_word_flags+=("--plan")
    flags+=("--project=")
    two_word_flags+=("--project")
    two_word_flags+=("-p")
    flags+=("--skip-pull")
    flags+=("--verbose")
    flags+=("-v")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_shuttle_help()
{
    last_command="shuttle_help"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--clean")
    flags+=("-c")
    flags+=("--plan=")
    two_word_flags+=("--plan")
    flags+=("--project=")
    two_word_flags+=("--project")
    two_word_flags+=("-p")
    flags+=("--skip-pull")
    flags+=("--verbose")
    flags+=("-v")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_shuttle_ls()
{
    last_command="shuttle_ls"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--template=")
    two_word_flags+=("--template")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--clean")
    flags+=("-c")
    flags+=("--plan=")
    two_word_flags+=("--plan")
    flags+=("--project=")
    two_word_flags+=("--project")
    two_word_flags+=("-p")
    flags+=("--skip-pull")
    flags+=("--verbose")
    flags+=("-v")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_shuttle_plan()
{
    last_command="shuttle_plan"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--template=")
    two_word_flags+=("--template")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--clean")
    flags+=("-c")
    flags+=("--plan=")
    two_word_flags+=("--plan")
    flags+=("--project=")
    two_word_flags+=("--project")
    two_word_flags+=("-p")
    flags+=("--skip-pull")
    flags+=("--verbose")
    flags+=("-v")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_shuttle_prepare()
{
    last_command="shuttle_prepare"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--clean")
    flags+=("-c")
    flags+=("--plan=")
    two_word_flags+=("--plan")
    flags+=("--project=")
    two_word_flags+=("--project")
    two_word_flags+=("-p")
    flags+=("--skip-pull")
    flags+=("--verbose")
    flags+=("-v")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_shuttle_run()
{
    last_command="shuttle_run"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--template=")
    two_word_flags+=("--template")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--validate")
    local_nonpersistent_flags+=("--validate")
    flags+=("--clean")
    flags+=("-c")
    flags+=("--plan=")
    two_word_flags+=("--plan")
    flags+=("--project=")
    two_word_flags+=("--project")
    two_word_flags+=("-p")
    flags+=("--skip-pull")
    flags+=("--verbose")
    flags+=("-v")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_shuttle_template()
{
    last_command="shuttle_template"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--delims=")
    two_word_flags+=("--delims")
    local_nonpersistent_flags+=("--delims")
    local_nonpersistent_flags+=("--delims=")
    flags+=("--ignore-project-overrides")
    local_nonpersistent_flags+=("--ignore-project-overrides")
    flags+=("--left-delim=")
    two_word_flags+=("--left-delim")
    local_nonpersistent_flags+=("--left-delim")
    local_nonpersistent_flags+=("--left-delim=")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--right-delim=")
    two_word_flags+=("--right-delim")
    local_nonpersistent_flags+=("--right-delim")
    local_nonpersistent_flags+=("--right-delim=")
    flags+=("--clean")
    flags+=("-c")
    flags+=("--plan=")
    two_word_flags+=("--plan")
    flags+=("--project=")
    two_word_flags+=("--project")
    two_word_flags+=("-p")
    flags+=("--skip-pull")
    flags+=("--verbose")
    flags+=("-v")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_shuttle_version()
{
    last_command="shuttle_version"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--commit")
    local_nonpersistent_flags+=("--commit")
    flags+=("--clean")
    flags+=("-c")
    flags+=("--plan=")
    two_word_flags+=("--plan")
    flags+=("--project=")
    two_word_flags+=("--project")
    two_word_flags+=("-p")
    flags+=("--skip-pull")
    flags+=("--verbose")
    flags+=("-v")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_shuttle_root_command()
{
    last_command="shuttle"

    command_aliases=()

    commands=()
    commands+=("completion")
    commands+=("documentation")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("docs")
        aliashash["docs"]="documentation"
    fi
    commands+=("get")
    commands+=("git-plan")
    commands+=("has")
    commands+=("help")
    commands+=("ls")
    commands+=("plan")
    commands+=("prepare")
    commands+=("run")
    commands+=("template")
    commands+=("version")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--clean")
    flags+=("-c")
    flags+=("--plan=")
    two_word_flags+=("--plan")
    flags+=("--project=")
    two_word_flags+=("--project")
    two_word_flags+=("-p")
    flags+=("--skip-pull")
    flags+=("--verbose")
    flags+=("-v")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

__start_shuttle()
{
    local cur prev words cword
    declare -A flaghash 2>/dev/null || :
    declare -A aliashash 2>/dev/null || :
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -s || return
    else
        __shuttle_init_completion -n "=" || return
    fi

    local c=0
    local flags=()
    local two_word_flags=()
    local local_nonpersistent_flags=()
    local flags_with_completion=()
    local flags_completion=()
    local commands=("shuttle")
    local must_have_one_flag=()
    local must_have_one_noun=()
    local has_completion_function
    local last_command
    local nouns=()

    __shuttle_handle_word
}

if [[ $(type -t compopt) = "builtin" ]]; then
    complete -o default -F __start_shuttle shuttle
else
    complete -o default -o nospace -F __start_shuttle shuttle
fi

# ex: ts=4 sw=4 et filetype=sh

BASH_COMPLETION_EOF
}
__shuttle_bash_source <(__shuttle_convert_bash_to_zsh)
_complete shuttle 2>/dev/null

#compdef hamctl

__hamctl_bash_source() {
	alias shopt=':'
	alias _expand=_bash_expand
	alias _complete=_bash_comp
	emulate -L sh
	setopt kshglob noshglob braceexpand
	source "$@"
}
__hamctl_type() {
	# -t is not supported by zsh
	if [ "$1" == "-t" ]; then
		shift
		# fake Bash 4 to disable "complete -o nospace". Instead
		# "compopt +-o nospace" is used in the code to toggle trailing
		# spaces. We don't support that, but leave trailing spaces on
		# all the time
		if [ "$1" = "__hamctl_compopt" ]; then
			echo builtin
			return 0
		fi
	fi
	type "$@"
}
__hamctl_compgen() {
	local completions w
	completions=( $(compgen "$@") ) || return $?
	# filter by given word as prefix
	while [[ "$1" = -* && "$1" != -- ]]; do
		shift
		shift
	done
	if [[ "$1" == -- ]]; then
		shift
	fi
	for w in "${completions[@]}"; do
		if [[ "${w}" = "$1"* ]]; then
			echo "${w}"
		fi
	done
}
__hamctl_compopt() {
	true # don't do anything. Not supported by bashcompinit in zsh
}
__hamctl_ltrim_colon_completions()
{
	if [[ "$1" == *:* && "$COMP_WORDBREAKS" == *:* ]]; then
		# Remove colon-word prefix from COMPREPLY items
		local colon_word=${1%${1##*:}}
		local i=${#COMPREPLY[*]}
		while [[ $((--i)) -ge 0 ]]; do
			COMPREPLY[$i]=${COMPREPLY[$i]#"$colon_word"}
		done
	fi
}
__hamctl_get_comp_words_by_ref() {
	cur="${COMP_WORDS[COMP_CWORD]}"
	prev="${COMP_WORDS[${COMP_CWORD}-1]}"
	words=("${COMP_WORDS[@]}")
	cword=("${COMP_CWORD[@]}")
}
__hamctl_filedir() {
	local RET OLD_IFS w qw
	__hamctl_debug "_filedir $@ cur=$cur"
	if [[ "$1" = \~* ]]; then
		# somehow does not work. Maybe, zsh does not call this at all
		eval echo "$1"
		return 0
	fi
	OLD_IFS="$IFS"
	IFS=$'\n'
	if [ "$1" = "-d" ]; then
		shift
		RET=( $(compgen -d) )
	else
		RET=( $(compgen -f) )
	fi
	IFS="$OLD_IFS"
	IFS="," __hamctl_debug "RET=${RET[@]} len=${#RET[@]}"
	for w in ${RET[@]}; do
		if [[ ! "${w}" = "${cur}"* ]]; then
			continue
		fi
		if eval "[[ \"\${w}\" = *.$1 || -d \"\${w}\" ]]"; then
			qw="$(__hamctl_quote "${w}")"
			if [ -d "${w}" ]; then
				COMPREPLY+=("${qw}/")
			else
				COMPREPLY+=("${qw}")
			fi
		fi
	done
}
__hamctl_quote() {
    if [[ $1 == \'* || $1 == \"* ]]; then
        # Leave out first character
        printf %q "${1:1}"
    else
	printf %q "$1"
    fi
}
autoload -U +X bashcompinit && bashcompinit
# use word boundary patterns for BSD or GNU sed
LWORD='[[:<:]]'
RWORD='[[:>:]]'
if sed --help 2>&1 | grep -q GNU; then
	LWORD='\<'
	RWORD='\>'
fi
__hamctl_convert_bash_to_zsh() {
	sed \
	-e 's/declare -F/whence -w/' \
	-e 's/_get_comp_words_by_ref "\$@"/_get_comp_words_by_ref "\$*"/' \
	-e 's/local \([a-zA-Z0-9_]*\)=/local \1; \1=/' \
	-e 's/flags+=("\(--.*\)=")/flags+=("\1"); two_word_flags+=("\1")/' \
	-e 's/must_have_one_flag+=("\(--.*\)=")/must_have_one_flag+=("\1")/' \
	-e "s/${LWORD}_filedir${RWORD}/__hamctl_filedir/g" \
	-e "s/${LWORD}_get_comp_words_by_ref${RWORD}/__hamctl_get_comp_words_by_ref/g" \
	-e "s/${LWORD}__ltrim_colon_completions${RWORD}/__hamctl_ltrim_colon_completions/g" \
	-e "s/${LWORD}compgen${RWORD}/__hamctl_compgen/g" \
	-e "s/${LWORD}compopt${RWORD}/__hamctl_compopt/g" \
	-e "s/${LWORD}declare${RWORD}/builtin declare/g" \
	-e "s/\\\$(type${RWORD}/\$(__hamctl_type/g" \
	<<'BASH_COMPLETION_EOF'
# bash completion for hamctl                               -*- shell-script -*-

__hamctl_debug()
{
    if [[ -n ${BASH_COMP_DEBUG_FILE} ]]; then
        echo "$*" >> "${BASH_COMP_DEBUG_FILE}"
    fi
}

# Homebrew on Macs have version 1.3 of bash-completion which doesn't include
# _init_completion. This is a very minimal version of that function.
__hamctl_init_completion()
{
    COMPREPLY=()
    _get_comp_words_by_ref "$@" cur prev words cword
}

__hamctl_index_of_word()
{
    local w word=$1
    shift
    index=0
    for w in "$@"; do
        [[ $w = "$word" ]] && return
        index=$((index+1))
    done
    index=-1
}

__hamctl_contains_word()
{
    local w word=$1; shift
    for w in "$@"; do
        [[ $w = "$word" ]] && return
    done
    return 1
}

__hamctl_handle_go_custom_completion()
{
    __hamctl_debug "${FUNCNAME[0]}: cur is ${cur}, words[*] is ${words[*]}, #words[@] is ${#words[@]}"

    local shellCompDirectiveError=1
    local shellCompDirectiveNoSpace=2
    local shellCompDirectiveNoFileComp=4
    local shellCompDirectiveFilterFileExt=8
    local shellCompDirectiveFilterDirs=16

    local out requestComp lastParam lastChar comp directive args

    # Prepare the command to request completions for the program.
    # Calling ${words[0]} instead of directly hamctl allows to handle aliases
    args=("${words[@]:1}")
    requestComp="${words[0]} __completeNoDesc ${args[*]}"

    lastParam=${words[$((${#words[@]}-1))]}
    lastChar=${lastParam:$((${#lastParam}-1)):1}
    __hamctl_debug "${FUNCNAME[0]}: lastParam ${lastParam}, lastChar ${lastChar}"

    if [ -z "${cur}" ] && [ "${lastChar}" != "=" ]; then
        # If the last parameter is complete (there is a space following it)
        # We add an extra empty parameter so we can indicate this to the go method.
        __hamctl_debug "${FUNCNAME[0]}: Adding extra empty parameter"
        requestComp="${requestComp} \"\""
    fi

    __hamctl_debug "${FUNCNAME[0]}: calling ${requestComp}"
    # Use eval to handle any environment variables and such
    out=$(eval "${requestComp}" 2>/dev/null)

    # Extract the directive integer at the very end of the output following a colon (:)
    directive=${out##*:}
    # Remove the directive
    out=${out%:*}
    if [ "${directive}" = "${out}" ]; then
        # There is not directive specified
        directive=0
    fi
    __hamctl_debug "${FUNCNAME[0]}: the completion directive is: ${directive}"
    __hamctl_debug "${FUNCNAME[0]}: the completions are: ${out[*]}"

    if [ $((directive & shellCompDirectiveError)) -ne 0 ]; then
        # Error code.  No completion.
        __hamctl_debug "${FUNCNAME[0]}: received error from custom completion go code"
        return
    else
        if [ $((directive & shellCompDirectiveNoSpace)) -ne 0 ]; then
            if [[ $(type -t compopt) = "builtin" ]]; then
                __hamctl_debug "${FUNCNAME[0]}: activating no space"
                compopt -o nospace
            fi
        fi
        if [ $((directive & shellCompDirectiveNoFileComp)) -ne 0 ]; then
            if [[ $(type -t compopt) = "builtin" ]]; then
                __hamctl_debug "${FUNCNAME[0]}: activating no file completion"
                compopt +o default
            fi
        fi
    fi

    if [ $((directive & shellCompDirectiveFilterFileExt)) -ne 0 ]; then
        # File extension filtering
        local fullFilter filter filteringCmd
        # Do not use quotes around the $out variable or else newline
        # characters will be kept.
        for filter in ${out[*]}; do
            fullFilter+="$filter|"
        done

        filteringCmd="_filedir $fullFilter"
        __hamctl_debug "File filtering command: $filteringCmd"
        $filteringCmd
    elif [ $((directive & shellCompDirectiveFilterDirs)) -ne 0 ]; then
        # File completion for directories only
        local subDir
        # Use printf to strip any trailing newline
        subdir=$(printf "%s" "${out[0]}")
        if [ -n "$subdir" ]; then
            __hamctl_debug "Listing directories in $subdir"
            __hamctl_handle_subdirs_in_dir_flag "$subdir"
        else
            __hamctl_debug "Listing directories in ."
            _filedir -d
        fi
    else
        while IFS='' read -r comp; do
            COMPREPLY+=("$comp")
        done < <(compgen -W "${out[*]}" -- "$cur")
    fi
}

__hamctl_handle_reply()
{
    __hamctl_debug "${FUNCNAME[0]}"
    local comp
    case $cur in
        -*)
            if [[ $(type -t compopt) = "builtin" ]]; then
                compopt -o nospace
            fi
            local allflags
            if [ ${#must_have_one_flag[@]} -ne 0 ]; then
                allflags=("${must_have_one_flag[@]}")
            else
                allflags=("${flags[*]} ${two_word_flags[*]}")
            fi
            while IFS='' read -r comp; do
                COMPREPLY+=("$comp")
            done < <(compgen -W "${allflags[*]}" -- "$cur")
            if [[ $(type -t compopt) = "builtin" ]]; then
                [[ "${COMPREPLY[0]}" == *= ]] || compopt +o nospace
            fi

            # complete after --flag=abc
            if [[ $cur == *=* ]]; then
                if [[ $(type -t compopt) = "builtin" ]]; then
                    compopt +o nospace
                fi

                local index flag
                flag="${cur%=*}"
                __hamctl_index_of_word "${flag}" "${flags_with_completion[@]}"
                COMPREPLY=()
                if [[ ${index} -ge 0 ]]; then
                    PREFIX=""
                    cur="${cur#*=}"
                    ${flags_completion[${index}]}
                    if [ -n "${ZSH_VERSION}" ]; then
                        # zsh completion needs --flag= prefix
                        eval "COMPREPLY=( \"\${COMPREPLY[@]/#/${flag}=}\" )"
                    fi
                fi
            fi
            return 0;
            ;;
    esac

    # check if we are handling a flag with special work handling
    local index
    __hamctl_index_of_word "${prev}" "${flags_with_completion[@]}"
    if [[ ${index} -ge 0 ]]; then
        ${flags_completion[${index}]}
        return
    fi

    # we are parsing a flag and don't have a special handler, no completion
    if [[ ${cur} != "${words[cword]}" ]]; then
        return
    fi

    local completions
    completions=("${commands[@]}")
    if [[ ${#must_have_one_noun[@]} -ne 0 ]]; then
        completions+=("${must_have_one_noun[@]}")
    elif [[ -n "${has_completion_function}" ]]; then
        # if a go completion function is provided, defer to that function
        __hamctl_handle_go_custom_completion
    fi
    if [[ ${#must_have_one_flag[@]} -ne 0 ]]; then
        completions+=("${must_have_one_flag[@]}")
    fi
    while IFS='' read -r comp; do
        COMPREPLY+=("$comp")
    done < <(compgen -W "${completions[*]}" -- "$cur")

    if [[ ${#COMPREPLY[@]} -eq 0 && ${#noun_aliases[@]} -gt 0 && ${#must_have_one_noun[@]} -ne 0 ]]; then
        while IFS='' read -r comp; do
            COMPREPLY+=("$comp")
        done < <(compgen -W "${noun_aliases[*]}" -- "$cur")
    fi

    if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
		if declare -F __hamctl_custom_func >/dev/null; then
			# try command name qualified custom func
			__hamctl_custom_func
		else
			# otherwise fall back to unqualified for compatibility
			declare -F __custom_func >/dev/null && __custom_func
		fi
    fi

    # available in bash-completion >= 2, not always present on macOS
    if declare -F __ltrim_colon_completions >/dev/null; then
        __ltrim_colon_completions "$cur"
    fi

    # If there is only 1 completion and it is a flag with an = it will be completed
    # but we don't want a space after the =
    if [[ "${#COMPREPLY[@]}" -eq "1" ]] && [[ $(type -t compopt) = "builtin" ]] && [[ "${COMPREPLY[0]}" == --*= ]]; then
       compopt -o nospace
    fi
}

# The arguments should be in the form "ext1|ext2|extn"
__hamctl_handle_filename_extension_flag()
{
    local ext="$1"
    _filedir "@(${ext})"
}

__hamctl_handle_subdirs_in_dir_flag()
{
    local dir="$1"
    pushd "${dir}" >/dev/null 2>&1 && _filedir -d && popd >/dev/null 2>&1 || return
}

__hamctl_handle_flag()
{
    __hamctl_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    # if a command required a flag, and we found it, unset must_have_one_flag()
    local flagname=${words[c]}
    local flagvalue
    # if the word contained an =
    if [[ ${words[c]} == *"="* ]]; then
        flagvalue=${flagname#*=} # take in as flagvalue after the =
        flagname=${flagname%=*} # strip everything after the =
        flagname="${flagname}=" # but put the = back
    fi
    __hamctl_debug "${FUNCNAME[0]}: looking for ${flagname}"
    if __hamctl_contains_word "${flagname}" "${must_have_one_flag[@]}"; then
        must_have_one_flag=()
    fi

    # if you set a flag which only applies to this command, don't show subcommands
    if __hamctl_contains_word "${flagname}" "${local_nonpersistent_flags[@]}"; then
      commands=()
    fi

    # keep flag value with flagname as flaghash
    # flaghash variable is an associative array which is only supported in bash > 3.
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        if [ -n "${flagvalue}" ] ; then
            flaghash[${flagname}]=${flagvalue}
        elif [ -n "${words[ $((c+1)) ]}" ] ; then
            flaghash[${flagname}]=${words[ $((c+1)) ]}
        else
            flaghash[${flagname}]="true" # pad "true" for bool flag
        fi
    fi

    # skip the argument to a two word flag
    if [[ ${words[c]} != *"="* ]] && __hamctl_contains_word "${words[c]}" "${two_word_flags[@]}"; then
			  __hamctl_debug "${FUNCNAME[0]}: found a flag ${words[c]}, skip the next argument"
        c=$((c+1))
        # if we are looking for a flags value, don't show commands
        if [[ $c -eq $cword ]]; then
            commands=()
        fi
    fi

    c=$((c+1))

}

__hamctl_handle_noun()
{
    __hamctl_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    if __hamctl_contains_word "${words[c]}" "${must_have_one_noun[@]}"; then
        must_have_one_noun=()
    elif __hamctl_contains_word "${words[c]}" "${noun_aliases[@]}"; then
        must_have_one_noun=()
    fi

    nouns+=("${words[c]}")
    c=$((c+1))
}

__hamctl_handle_command()
{
    __hamctl_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    local next_command
    if [[ -n ${last_command} ]]; then
        next_command="_${last_command}_${words[c]//:/__}"
    else
        if [[ $c -eq 0 ]]; then
            next_command="_hamctl_root_command"
        else
            next_command="_${words[c]//:/__}"
        fi
    fi
    c=$((c+1))
    __hamctl_debug "${FUNCNAME[0]}: looking for ${next_command}"
    declare -F "$next_command" >/dev/null && $next_command
}

__hamctl_handle_word()
{
    if [[ $c -ge $cword ]]; then
        __hamctl_handle_reply
        return
    fi
    __hamctl_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"
    if [[ "${words[c]}" == -* ]]; then
        __hamctl_handle_flag
    elif __hamctl_contains_word "${words[c]}" "${commands[@]}"; then
        __hamctl_handle_command
    elif [[ $c -eq 0 ]]; then
        __hamctl_handle_command
    elif __hamctl_contains_word "${words[c]}" "${command_aliases[@]}"; then
        # aliashash variable is an associative array which is only supported in bash > 3.
        if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
            words[c]=${aliashash[${words[c]}]}
            __hamctl_handle_command
        else
            __hamctl_handle_noun
        fi
    else
        __hamctl_handle_noun
    fi
    __hamctl_handle_word
}


__hamctl_get_environments()
{
	local template
	template=$'{{ range $k, $v := . }}{{ $k }} {{ end }}'
	local shuttle_out
	if shuttle_out=$(shuttle --skip-pull get k8s  --template="${template}" 2>/dev/null); then
		# remove "local" from possible environments as it has no use for hamctl
		shuttle_out=${shuttle_out[@]//local}
		COMPREPLY=( $( compgen -W "${shuttle_out[@]}" -- "$cur" ) )
	fi
}

__hamctl_get_namespaces()
{
	local template
	template="{{ range .items  }}{{ .metadata.name }} {{ end }}"
	local kubectl_out
	if kubectl_out=$(kubectl get -o template --template="${template}" namespace 2>/dev/null); then
		COMPREPLY=( $( compgen -W "${kubectl_out[*]}" -- "$cur" ) )
	fi
}

__hamctl_get_branches()
{
	local git_out
	if git_out=$(git branch --remote | grep -v HEAD | sed 's/[ \t*]origin\///' 2>/dev/null); then
		COMPREPLY=( $( compgen -W "${git_out[*]}" -- "$cur" ) )
	fi
}

_hamctl_completion()
{
    last_command="hamctl_completion"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")
    local_nonpersistent_flags+=("--help")
    local_nonpersistent_flags+=("-h")
    flags+=("--http-auth-token=")
    two_word_flags+=("--http-auth-token")
    flags+=("--http-base-url=")
    two_word_flags+=("--http-base-url")
    flags+=("--http-timeout=")
    two_word_flags+=("--http-timeout")
    flags+=("--service=")
    two_word_flags+=("--service")
    flags+=("--user-email=")
    two_word_flags+=("--user-email")

    must_have_one_flag=()
    must_have_one_noun=()
    must_have_one_noun+=("bash")
    must_have_one_noun+=("zsh")
    noun_aliases=()
}

_hamctl_describe_artifact()
{
    last_command="hamctl_describe_artifact"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--count=")
    two_word_flags+=("--count")
    local_nonpersistent_flags+=("--count")
    local_nonpersistent_flags+=("--count=")
    flags+=("--template=")
    two_word_flags+=("--template")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--http-auth-token=")
    two_word_flags+=("--http-auth-token")
    flags+=("--http-base-url=")
    two_word_flags+=("--http-base-url")
    flags+=("--http-timeout=")
    two_word_flags+=("--http-timeout")
    flags+=("--service=")
    two_word_flags+=("--service")
    flags+=("--user-email=")
    two_word_flags+=("--user-email")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_hamctl_describe_release()
{
    last_command="hamctl_describe_release"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--count=")
    two_word_flags+=("--count")
    two_word_flags+=("-c")
    local_nonpersistent_flags+=("--count")
    local_nonpersistent_flags+=("--count=")
    local_nonpersistent_flags+=("-c")
    flags+=("--env=")
    two_word_flags+=("--env")
    flags_with_completion+=("--env")
    flags_completion+=("__hamctl_get_environments")
    two_word_flags+=("-e")
    flags_with_completion+=("-e")
    flags_completion+=("__hamctl_get_environments")
    local_nonpersistent_flags+=("--env")
    local_nonpersistent_flags+=("--env=")
    local_nonpersistent_flags+=("-e")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    flags_with_completion+=("--namespace")
    flags_completion+=("__hamctl_get_namespaces")
    two_word_flags+=("-n")
    flags_with_completion+=("-n")
    flags_completion+=("__hamctl_get_namespaces")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--template=")
    two_word_flags+=("--template")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--http-auth-token=")
    two_word_flags+=("--http-auth-token")
    flags+=("--http-base-url=")
    two_word_flags+=("--http-base-url")
    flags+=("--http-timeout=")
    two_word_flags+=("--http-timeout")
    flags+=("--service=")
    two_word_flags+=("--service")
    flags+=("--user-email=")
    two_word_flags+=("--user-email")

    must_have_one_flag=()
    must_have_one_flag+=("--env=")
    must_have_one_flag+=("-e")
    must_have_one_noun=()
    noun_aliases=()
}

_hamctl_describe()
{
    last_command="hamctl_describe"

    command_aliases=()

    commands=()
    commands+=("artifact")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("artifacts")
        aliashash["artifacts"]="artifact"
    fi
    commands+=("release")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("releases")
        aliashash["releases"]="release"
    fi

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--http-auth-token=")
    two_word_flags+=("--http-auth-token")
    flags+=("--http-base-url=")
    two_word_flags+=("--http-base-url")
    flags+=("--http-timeout=")
    two_word_flags+=("--http-timeout")
    flags+=("--service=")
    two_word_flags+=("--service")
    flags+=("--user-email=")
    two_word_flags+=("--user-email")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_hamctl_help()
{
    last_command="hamctl_help"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--http-auth-token=")
    two_word_flags+=("--http-auth-token")
    flags+=("--http-base-url=")
    two_word_flags+=("--http-base-url")
    flags+=("--http-timeout=")
    two_word_flags+=("--http-timeout")
    flags+=("--service=")
    two_word_flags+=("--service")
    flags+=("--user-email=")
    two_word_flags+=("--user-email")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_hamctl_policy_apply_auto-release()
{
    last_command="hamctl_policy_apply_auto-release"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--branch=")
    two_word_flags+=("--branch")
    flags_with_completion+=("--branch")
    flags_completion+=("__hamctl_get_branches")
    two_word_flags+=("-b")
    flags_with_completion+=("-b")
    flags_completion+=("__hamctl_get_branches")
    local_nonpersistent_flags+=("--branch")
    local_nonpersistent_flags+=("--branch=")
    local_nonpersistent_flags+=("-b")
    flags+=("--env=")
    two_word_flags+=("--env")
    flags_with_completion+=("--env")
    flags_completion+=("__hamctl_get_environments")
    two_word_flags+=("-e")
    flags_with_completion+=("-e")
    flags_completion+=("__hamctl_get_environments")
    local_nonpersistent_flags+=("--env")
    local_nonpersistent_flags+=("--env=")
    local_nonpersistent_flags+=("-e")
    flags+=("--http-auth-token=")
    two_word_flags+=("--http-auth-token")
    flags+=("--http-base-url=")
    two_word_flags+=("--http-base-url")
    flags+=("--http-timeout=")
    two_word_flags+=("--http-timeout")
    flags+=("--service=")
    two_word_flags+=("--service")
    flags+=("--user-email=")
    two_word_flags+=("--user-email")

    must_have_one_flag=()
    must_have_one_flag+=("--branch=")
    must_have_one_flag+=("-b")
    must_have_one_flag+=("--env=")
    must_have_one_flag+=("-e")
    must_have_one_noun=()
    noun_aliases=()
}

_hamctl_policy_apply_branch-restriction()
{
    last_command="hamctl_policy_apply_branch-restriction"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--branch-regex=")
    two_word_flags+=("--branch-regex")
    flags_with_completion+=("--branch-regex")
    flags_completion+=("__hamctl_get_branches")
    local_nonpersistent_flags+=("--branch-regex")
    local_nonpersistent_flags+=("--branch-regex=")
    flags+=("--env=")
    two_word_flags+=("--env")
    flags_with_completion+=("--env")
    flags_completion+=("__hamctl_get_environments")
    two_word_flags+=("-e")
    flags_with_completion+=("-e")
    flags_completion+=("__hamctl_get_environments")
    local_nonpersistent_flags+=("--env")
    local_nonpersistent_flags+=("--env=")
    local_nonpersistent_flags+=("-e")
    flags+=("--http-auth-token=")
    two_word_flags+=("--http-auth-token")
    flags+=("--http-base-url=")
    two_word_flags+=("--http-base-url")
    flags+=("--http-timeout=")
    two_word_flags+=("--http-timeout")
    flags+=("--service=")
    two_word_flags+=("--service")
    flags+=("--user-email=")
    two_word_flags+=("--user-email")

    must_have_one_flag=()
    must_have_one_flag+=("--branch-regex=")
    must_have_one_flag+=("--env=")
    must_have_one_flag+=("-e")
    must_have_one_noun=()
    noun_aliases=()
}

_hamctl_policy_apply()
{
    last_command="hamctl_policy_apply"

    command_aliases=()

    commands=()
    commands+=("auto-release")
    commands+=("branch-restriction")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--http-auth-token=")
    two_word_flags+=("--http-auth-token")
    flags+=("--http-base-url=")
    two_word_flags+=("--http-base-url")
    flags+=("--http-timeout=")
    two_word_flags+=("--http-timeout")
    flags+=("--service=")
    two_word_flags+=("--service")
    flags+=("--user-email=")
    two_word_flags+=("--user-email")

    must_have_one_flag=()
    must_have_one_noun=()
    must_have_one_noun+=("auto-release")
    must_have_one_noun+=("branch-restriction")
    noun_aliases=()
}

_hamctl_policy_delete()
{
    last_command="hamctl_policy_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--http-auth-token=")
    two_word_flags+=("--http-auth-token")
    flags+=("--http-base-url=")
    two_word_flags+=("--http-base-url")
    flags+=("--http-timeout=")
    two_word_flags+=("--http-timeout")
    flags+=("--service=")
    two_word_flags+=("--service")
    flags+=("--user-email=")
    two_word_flags+=("--user-email")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_hamctl_policy_list()
{
    last_command="hamctl_policy_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--http-auth-token=")
    two_word_flags+=("--http-auth-token")
    flags+=("--http-base-url=")
    two_word_flags+=("--http-base-url")
    flags+=("--http-timeout=")
    two_word_flags+=("--http-timeout")
    flags+=("--service=")
    two_word_flags+=("--service")
    flags+=("--user-email=")
    two_word_flags+=("--user-email")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_hamctl_policy()
{
    last_command="hamctl_policy"

    command_aliases=()

    commands=()
    commands+=("apply")
    commands+=("delete")
    commands+=("list")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--http-auth-token=")
    two_word_flags+=("--http-auth-token")
    flags+=("--http-base-url=")
    two_word_flags+=("--http-base-url")
    flags+=("--http-timeout=")
    two_word_flags+=("--http-timeout")
    flags+=("--service=")
    two_word_flags+=("--service")
    flags+=("--user-email=")
    two_word_flags+=("--user-email")

    must_have_one_flag=()
    must_have_one_noun=()
    must_have_one_noun+=("apply")
    must_have_one_noun+=("delete")
    must_have_one_noun+=("list")
    noun_aliases=()
}

_hamctl_promote()
{
    last_command="hamctl_promote"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--env=")
    two_word_flags+=("--env")
    flags_with_completion+=("--env")
    flags_completion+=("__hamctl_get_environments")
    two_word_flags+=("-e")
    flags_with_completion+=("-e")
    flags_completion+=("__hamctl_get_environments")
    local_nonpersistent_flags+=("--env")
    local_nonpersistent_flags+=("--env=")
    local_nonpersistent_flags+=("-e")
    flags+=("--from-env=")
    two_word_flags+=("--from-env")
    flags_with_completion+=("--from-env")
    flags_completion+=("__hamctl_get_environments")
    local_nonpersistent_flags+=("--from-env")
    local_nonpersistent_flags+=("--from-env=")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    flags_with_completion+=("--namespace")
    flags_completion+=("__hamctl_get_namespaces")
    two_word_flags+=("-n")
    flags_with_completion+=("-n")
    flags_completion+=("__hamctl_get_namespaces")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--http-auth-token=")
    two_word_flags+=("--http-auth-token")
    flags+=("--http-base-url=")
    two_word_flags+=("--http-base-url")
    flags+=("--http-timeout=")
    two_word_flags+=("--http-timeout")
    flags+=("--service=")
    two_word_flags+=("--service")
    flags+=("--user-email=")
    two_word_flags+=("--user-email")

    must_have_one_flag=()
    must_have_one_flag+=("--env=")
    must_have_one_flag+=("-e")
    must_have_one_noun=()
    noun_aliases=()
}

_hamctl_release()
{
    last_command="hamctl_release"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--artifact=")
    two_word_flags+=("--artifact")
    local_nonpersistent_flags+=("--artifact")
    local_nonpersistent_flags+=("--artifact=")
    flags+=("--branch=")
    two_word_flags+=("--branch")
    flags_with_completion+=("--branch")
    flags_completion+=("__hamctl_get_branches")
    two_word_flags+=("-b")
    flags_with_completion+=("-b")
    flags_completion+=("__hamctl_get_branches")
    local_nonpersistent_flags+=("--branch")
    local_nonpersistent_flags+=("--branch=")
    local_nonpersistent_flags+=("-b")
    flags+=("--env=")
    two_word_flags+=("--env")
    flags_with_completion+=("--env")
    flags_completion+=("__hamctl_get_environments")
    two_word_flags+=("-e")
    flags_with_completion+=("-e")
    flags_completion+=("__hamctl_get_environments")
    local_nonpersistent_flags+=("--env")
    local_nonpersistent_flags+=("--env=")
    local_nonpersistent_flags+=("-e")
    flags+=("--http-auth-token=")
    two_word_flags+=("--http-auth-token")
    flags+=("--http-base-url=")
    two_word_flags+=("--http-base-url")
    flags+=("--http-timeout=")
    two_word_flags+=("--http-timeout")
    flags+=("--service=")
    two_word_flags+=("--service")
    flags+=("--user-email=")
    two_word_flags+=("--user-email")

    must_have_one_flag=()
    must_have_one_flag+=("--env=")
    must_have_one_flag+=("-e")
    must_have_one_noun=()
    noun_aliases=()
}

_hamctl_rollback()
{
    last_command="hamctl_rollback"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--artifact=")
    two_word_flags+=("--artifact")
    local_nonpersistent_flags+=("--artifact")
    local_nonpersistent_flags+=("--artifact=")
    flags+=("--env=")
    two_word_flags+=("--env")
    flags_with_completion+=("--env")
    flags_completion+=("__hamctl_get_environments")
    two_word_flags+=("-e")
    flags_with_completion+=("-e")
    flags_completion+=("__hamctl_get_environments")
    local_nonpersistent_flags+=("--env")
    local_nonpersistent_flags+=("--env=")
    local_nonpersistent_flags+=("-e")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    flags_with_completion+=("--namespace")
    flags_completion+=("__hamctl_get_namespaces")
    two_word_flags+=("-n")
    flags_with_completion+=("-n")
    flags_completion+=("__hamctl_get_namespaces")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--http-auth-token=")
    two_word_flags+=("--http-auth-token")
    flags+=("--http-base-url=")
    two_word_flags+=("--http-base-url")
    flags+=("--http-timeout=")
    two_word_flags+=("--http-timeout")
    flags+=("--service=")
    two_word_flags+=("--service")
    flags+=("--user-email=")
    two_word_flags+=("--user-email")

    must_have_one_flag=()
    must_have_one_flag+=("--env=")
    must_have_one_flag+=("-e")
    must_have_one_noun=()
    noun_aliases=()
}

_hamctl_status()
{
    last_command="hamctl_status"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    flags_with_completion+=("--namespace")
    flags_completion+=("__hamctl_get_namespaces")
    two_word_flags+=("-n")
    flags_with_completion+=("-n")
    flags_completion+=("__hamctl_get_namespaces")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--http-auth-token=")
    two_word_flags+=("--http-auth-token")
    flags+=("--http-base-url=")
    two_word_flags+=("--http-base-url")
    flags+=("--http-timeout=")
    two_word_flags+=("--http-timeout")
    flags+=("--service=")
    two_word_flags+=("--service")
    flags+=("--user-email=")
    two_word_flags+=("--user-email")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_hamctl_version()
{
    last_command="hamctl_version"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--http-auth-token=")
    two_word_flags+=("--http-auth-token")
    flags+=("--http-base-url=")
    two_word_flags+=("--http-base-url")
    flags+=("--http-timeout=")
    two_word_flags+=("--http-timeout")
    flags+=("--service=")
    two_word_flags+=("--service")
    flags+=("--user-email=")
    two_word_flags+=("--user-email")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_hamctl_root_command()
{
    last_command="hamctl"

    command_aliases=()

    commands=()
    commands+=("completion")
    commands+=("describe")
    commands+=("help")
    commands+=("policy")
    commands+=("promote")
    commands+=("release")
    commands+=("rollback")
    commands+=("status")
    commands+=("version")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--http-auth-token=")
    two_word_flags+=("--http-auth-token")
    flags+=("--http-base-url=")
    two_word_flags+=("--http-base-url")
    flags+=("--http-timeout=")
    two_word_flags+=("--http-timeout")
    flags+=("--service=")
    two_word_flags+=("--service")
    flags+=("--user-email=")
    two_word_flags+=("--user-email")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

__start_hamctl()
{
    local cur prev words cword
    declare -A flaghash 2>/dev/null || :
    declare -A aliashash 2>/dev/null || :
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -s || return
    else
        __hamctl_init_completion -n "=" || return
    fi

    local c=0
    local flags=()
    local two_word_flags=()
    local local_nonpersistent_flags=()
    local flags_with_completion=()
    local flags_completion=()
    local commands=("hamctl")
    local must_have_one_flag=()
    local must_have_one_noun=()
    local has_completion_function
    local last_command
    local nouns=()

    __hamctl_handle_word
}

if [[ $(type -t compopt) = "builtin" ]]; then
    complete -o default -F __start_hamctl hamctl
else
    complete -o default -o nospace -F __start_hamctl hamctl
fi

# ex: ts=4 sw=4 et filetype=sh

BASH_COMPLETION_EOF
}
__hamctl_bash_source <(__hamctl_convert_bash_to_zsh)
_complete hamctl 2>/dev/null
