#!/usr/bin/env bash
# Shared port/IP configuration prompt used by node_setup.sh and na_protect.sh.
# Source this file after colors and SEP are defined.
# Requires: JUNGLE_ENV already sourced (or vars absent = defaults used).
# Exports:  SSH_PORT PANEL_IP BESZEL_PORT NODE_PORT XHTTP_PORT GRPC_PORT

collect_node_config() {
    echo -e "$SEP"
    echo -e "${BOLD}  Configuration — defaults shown in brackets${NC}"
    echo -e "$SEP"
    echo ""

    read -rp "  SSH port         [${JUNGLE_SSH_PORT:-1702}]:           " _v;  SSH_PORT="${_v:-${JUNGLE_SSH_PORT:-1702}}"
    read -rp "  Panel IP         [${JUNGLE_PANEL_IP:-}]:  "              _v;  PANEL_IP="${_v:-${JUNGLE_PANEL_IP:-}}"
    read -rp "  Beszel port      [${JUNGLE_BESZEL_PORT:-45876}]:          " _v; BESZEL_PORT="${_v:-${JUNGLE_BESZEL_PORT:-45876}}"
    read -rp "  Node port        [${JUNGLE_NODE_PORT:-2222}]:           "  _v; NODE_PORT="${_v:-${JUNGLE_NODE_PORT:-2222}}"
    read -rp "  XHTTP port       [${JUNGLE_XHTTP_PORT:-8443}]:           " _v; XHTTP_PORT="${_v:-${JUNGLE_XHTTP_PORT:-8443}}"
    read -rp "  gRPC port        [${JUNGLE_GRPC_PORT:-9443}]:           "  _v; GRPC_PORT="${_v:-${JUNGLE_GRPC_PORT:-9443}}"

    echo ""
    echo -e "$SEP"
    echo -e "${BOLD}  Summary${NC}"
    echo -e "$SEP"
    echo -e "  SSH_PORT    = ${CYAN}$SSH_PORT${NC}"
    echo -e "  PANEL_IP    = ${CYAN}$PANEL_IP${NC}"
    echo -e "  BESZEL_PORT = ${CYAN}$BESZEL_PORT${NC}"
    echo -e "  NODE_PORT   = ${CYAN}$NODE_PORT${NC}"
    echo -e "  XHTTP_PORT  = ${CYAN}$XHTTP_PORT${NC}"
    echo -e "  GRPC_PORT   = ${CYAN}$GRPC_PORT${NC}"
    echo -e "$SEP"
    echo ""

    export SSH_PORT PANEL_IP BESZEL_PORT NODE_PORT XHTTP_PORT GRPC_PORT
}
