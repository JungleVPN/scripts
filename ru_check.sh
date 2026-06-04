#!/usr/bin/env bash
# =============================================================================
# ru_check.sh — Connectivity check from this server to major Russian services
#
# Usage (standalone):
#   bash ru_check.sh
#   bash <(curl -Ls https://raw.githubusercontent.com/JungleVPN/scripts/main/ru_check.sh)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
GRAY='\033[38;5;8m'; BOLD='\033[1m'; NC='\033[0m'

SEP="${GRAY}$(printf '─%.0s' $(seq 1 54))${NC}"

# ── Header ────────────────────────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat <<'BANNER'
  ╔════════════════════════════════════════════════════════╗
  ║         The Jungle — RU Services Connectivity          ║
  ║     Testing access to major Russian websites           ║
  ╚════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# ── Check function ────────────────────────────────────────────────────────────
check() {
    local name="$1"
    local url="$2"

    local result
    result=$(curl -s -o /dev/null \
        -w "%{http_code} %{time_total}" \
        --connect-timeout 10 \
        --max-time 15 \
        -L "$url" 2>/dev/null) || result="000 0"

    local code="${result%% *}"
    local time="${result##* }"
    local ms
    ms=$(awk "BEGIN {printf \"%.0f\", $time * 1000}")

    if [[ "$code" =~ ^(200|301|302|303|403|404) ]]; then
        printf "  ${GREEN}✓${NC} %-30s ${GRAY}%s${NC} ${GREEN}%s ms${NC}\n" "$name" "$code" "$ms"
    elif [[ "$code" == "000" ]]; then
        printf "  ${RED}✗${NC} %-30s ${RED}unreachable${NC}\n" "$name"
    else
        printf "  ${YELLOW}?${NC} %-30s ${GRAY}%s${NC} ${YELLOW}%s ms${NC}\n" "$name" "$code" "$ms"
    fi
}

# ── Run checks ────────────────────────────────────────────────────────────────

echo -e "$SEP"
echo -e "  ${BOLD}Government & Public Services${NC}"
echo -e "$SEP"
check "Gosuslugi"          "https://gosuslugi.ru"
check "Nalog.ru (FNS)"     "https://nalog.ru"
check "Mos.ru"             "https://mos.ru"
check "SFR (Pension Fund)" "https://sfr.gov.ru"
check "CBR (Central Bank)" "https://cbr.ru"
check "MVD"                "https://mvd.ru"

echo ""
echo -e "$SEP"
echo -e "  ${BOLD}Banking${NC}"
echo -e "$SEP"
check "Sber"               "https://sber.ru"
check "VTB"                "https://vtb.ru"
check "T-Bank"             "https://tbank.ru"
check "Alfa Bank"          "https://alfabank.ru"
check "Raiffeisen"         "https://raiffeisen.ru"
check "Gazprombank"        "https://gazprombank.ru"

echo ""
echo -e "$SEP"
echo -e "  ${BOLD}Social & Media${NC}"
echo -e "$SEP"
check "VKontakte"          "https://vk.com"
check "Odnoklassniki"      "https://ok.ru"
check "Yandex"             "https://yandex.ru"
check "Mail.ru"            "https://mail.ru"
check "Dzen"               "https://dzen.ru"
check "RuTube"             "https://rutube.ru"

echo ""
echo -e "$SEP"
echo -e "  ${BOLD}E-commerce & Services${NC}"
echo -e "$SEP"
check "Ozon"               "https://ozon.ru"
check "Wildberries"        "https://wildberries.ru"
check "Avito"              "https://avito.ru"
check "CDEK"               "https://cdek.ru"
check "DNS Shop"           "https://dns-shop.ru"

echo ""
echo -e "$SEP"
printf "  ${GRAY}%-30s  %-10s  %s${NC}\n" "Legend:" "✓  reachable" "✗  unreachable  ?  unexpected code"
echo -e "$SEP"
echo ""
