function gomodgraph() {
    if ! [ -x "$(command -v dot)" ]; then
        echo 'Error: dot not available in PATH. Install with "brew install graphviz" and retry.'
        return
    fi
    
    if ! [ -x "$(command -v modgraphviz)" ]; then
        echo 'modgraphviz not found. Installing now...'
        (mkdir /tmp/modgraphviz && go get golang.org/x/exp/cmd/modgraphviz)
    fi
    
    go mod graph | modgraphviz | dot -Tpng | open -f -a /System/Applications/Preview.app
}

function sourceLocalEnv() {
    set -a # automatically export all variables
    source local.env
    set +a
}

function gowtest() {
    set -a # automatically export all variables
    source local.env
    set +a
    
    args=${@:-./...}
    nodemon --ext go --ignore "**/vendor/**" -x "gotest "$args" || exit 1"
}

function gorun() {
    set -a # automatically export all variables
    source local.env
    set +a

    go run cmd/main.go
}

function gowbuild() {
    args=${@:-cmd/main.go}
    nodemon --ext go -x "go build $args || exit 1"
}

function gowbuildall() {
    args=${@:-./...}
    nodemon --ext go -x "go build $args || exit 1"
}
