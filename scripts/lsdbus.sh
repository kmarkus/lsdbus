#!/bin/bash

VERSIONS=(5.1 5.3 5.4 5.5 jit)
GRN='\e[0;32m'; RED='\e[0;31m'; CYA='\e[0;36m'; WHT='\e[0;37m'; RST='\e[0m'

USE_MXML="${USE_MXML:-1}"
USE_EXPAT="${USE_EXPAT:-0}"

usage() {
    echo -e "usage: $(basename $0) <command> [versions...]"
    echo
    echo -e "commands:"
    echo -e "  build    configure and build (cmake flags re-applied on every run)"
    echo -e "  install  sudo make install"
    echo -e "  test     run test suite"
    echo -e "  help     show this message"
    echo
    echo -e "known versions: ${GRN}${VERSIONS[*]}${RST}"
    echo -e "default: all versions"
    echo
    echo -e "env vars (build):"
    echo -e "  USE_MXML=1|0   mxml C backend       (current: ${CYA}${USE_MXML}${RST})"
    echo -e "  USE_EXPAT=1|0  luaexpat Lua backend  (current: ${CYA}${USE_EXPAT}${RST})"
    echo -e "env vars (test):"
    echo -e "  BUS=default    D-Bus bus to use      (current: ${CYA}${BUS:-default}${RST})"
    echo -e "  REPEAT=10      luaunit repeat count  (current: ${CYA}${REPEAT:-10}${RST})"
    echo
    echo -e "examples:"
    echo -e "  $(basename $0) build"
    echo -e "  $(basename $0) build 5.4 jit"
    echo -e "  USE_MXML=0 USE_EXPAT=1 $(basename $0) build 5.4"
    echo -e "  $(basename $0) test jit"
    echo -e "  BUS=user REPEAT=1 $(basename $0) test"
}

resolve_versions() {
    if [[ $# -eq 0 ]]; then
        echo "${VERSIONS[@]}"
        return
    fi
    for v in "$@"; do
        local ok=0
        for kv in "${VERSIONS[@]}"; do [[ "$v" == "$kv" ]] && ok=1 && break; done
        if [[ $ok -eq 0 ]]; then
            echo -e "${RED}error: unknown version '$v' (known: ${VERSIONS[*]})${RST}" >&2
            exit 1
        fi
    done
    echo "$@"
}

cmd_build() {
    local vers
    read -ra vers <<< "$(resolve_versions "$@")"
    local xml_info="USE_MXML=${CYA}${USE_MXML}${RST} USE_EXPAT=${CYA}${USE_EXPAT}${RST}"
    for v in "${vers[@]}"; do
        echo -e "${GRN}==> build $v${RST} ($xml_info)"
        mkdir -p "build-$v"
        pushd "build-$v" > /dev/null
        cmake ../ -DCONFIG_LUA_VER=$v -DCMAKE_BUILD_TYPE=Debug \
              -DUSE_MXML=${USE_MXML} -DUSE_EXPAT=${USE_EXPAT}
        make -j$(nproc)
        popd > /dev/null
    done
}

cmd_install() {
    local vers
    read -ra vers <<< "$(resolve_versions "$@")"
    for v in "${vers[@]}"; do
        echo -e "${GRN}==> install $v${RST}"
        pushd "build-$v" > /dev/null
        sudo make install
        popd > /dev/null
    done
}

cmd_test() {
    local vers
    read -ra vers <<< "$(resolve_versions "$@")"
    local bus="${BUS:-default}"
    local repeat="${REPEAT:-10}"
    local failed=()
    for v in "${vers[@]}"; do
        echo -e "running with ${GRN}$v${RST} on bus ${RED}${bus}${RST} (repeat=${CYA}${repeat}${RST})"
        LSDBUS_BUS=$bus LUA_VERSION=$v ./scripts/test-runner.sh -r $repeat -q -s
        [[ $? -ne 0 ]] && failed+=("$v")
        echo -e "${WHT}==============================================${RST}"
    done
    if [[ ${#failed[@]} -gt 0 ]]; then
        echo -e "${RED}FAILED: ${failed[*]}${RST}"
        exit 1
    fi
}

case "$1" in
    build)   shift; cmd_build   "$@" ;;
    install) shift; cmd_install "$@" ;;
    test)    shift; cmd_test    "$@" ;;
    help|"") usage ;;
    *) echo -e "${RED}error: unknown command '$1'${RST}"; echo; usage; exit 1 ;;
esac
