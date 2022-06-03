export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
export PATH="${PATH}:${HOME}/.krew/bin"
export PATH="/usr/local/opt/curl-openssl/bin:$PATH"

export SRC_ENDPOINT=https://sourcegraph.lunar.tech

export LOG_CONSOLE_AS_JSON=false

LW_PATH=lunar

alias curl=/usr/local/opt/curl/bin/curl

source ~/.zsh-config/git.zsh
source ~/.zsh-config/go.zsh
source ~/.zsh-config/secret.zsh
source ~/.zsh-config/docker.zsh
source ~/.zsh-config/nvm.zsh
source ~/.zsh-config/completion.zsh
source ~/.zsh-config/alias.zsh
source ~/.zsh-config/kubernetes.zsh
source ~/.zsh-config/mkdocs.zsh
