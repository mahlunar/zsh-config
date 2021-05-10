export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
export PATH="${PATH}:${HOME}/.krew/bin"

export SRC_ENDPOINT=https://sourcegraph.lunar.tech

export LOG_CONSOLE_AS_JSON=false

LW_PATH=lunar

alias s="shuttle"
alias sr="shuttle run --skip-pull"

alias h="hamctl"
alias gocode="cd /Users/martinankerhave/lunar/Github"
alias bs="eval 'open https://backstage.lunar.tech/'"

source ~/.zsh-config/git.zsh
source ~/.zsh-config/go.zsh
source ~/.zsh-config/secret.zsh
source ~/.zsh-config/docker.zsh