#!/usr/bin/env bash
# teste-conectividade.sh
# Verifica gateway, DNS e a matriz de acesso (o que o firewall deve liberar e bloquear).
#
# Uso:  sudo bash teste-conectividade.sh [cliente|web|banco|samba|roteador]
#       (sem argumento, o papel e detectado pelo IP da VM)
# Modo: MODO=final (padrao, estado de entrega) ou MODO=dev (durante a instalacao)
# Saida: [PASS]/[FAIL]/[AVISO]/[INFO] + log em ./resultados/. Codigo de saida != 0 se houver FAIL.

set -u

# ----------------------------------------------------------------------
# Configuração padrão (sobrescreva com variáveis de ambiente, ex.: WEB=10.0.0.5)
# ----------------------------------------------------------------------
GW_DMZ=${GW_DMZ:-192.168.10.1}
GW_LAN=${GW_LAN:-192.168.20.1}
GW_DB=${GW_DB:-192.168.30.1}
WEB=${WEB:-192.168.10.10}
FILES=${FILES:-192.168.20.10}
DB=${DB:-192.168.30.10}
INTERNET=${INTERNET:-8.8.8.8}
DOMINIO=${DOMINIO:-projeto.local}
WAN_IF=${WAN_IF:-ens33}
LAN_IF=${LAN_IF:-ens38}
# MODO=final -> estado de entrega (regra temporária de internet REMOVIDA)
# MODO=dev   -> durante a instalação (Web e Banco ainda acessam a internet)
MODO=${MODO:-final}
TIMEOUT=${TIMEOUT:-3}
RESULT_DIR=${RESULT_DIR:-./resultados}

PASS=0; FAIL=0; WARN=0
pass()  { printf '[PASS]  %s\n' "$*"; PASS=$((PASS+1)); }
fail()  { printf '[FAIL]  %s\n' "$*"; FAIL=$((FAIL+1)); }
warn()  { printf '[AVISO] %s\n' "$*"; WARN=$((WARN+1)); }
info()  { printf '[INFO]  %s\n' "$*"; }
secao() { printf '\n== %s ==\n' "$*"; }

# Detecta o papel da VM pelo IP configurado nela
meu_papel() {
  local ips; ips=$(ip -4 -o addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
  if grep -qxF "$GW_LAN" <<<"$ips" && grep -qxF "$GW_DMZ" <<<"$ips"; then echo roteador; return; fi
  if grep -qxF "$WEB"   <<<"$ips"; then echo web;    return; fi
  if grep -qxF "$DB"    <<<"$ips"; then echo banco;  return; fi
  if grep -qxF "$FILES" <<<"$ips"; then echo samba;  return; fi
  if grep -q '^192\.168\.20\.' <<<"$ips"; then echo cliente; return; fi
  echo ""
}

precisa_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Este papel precisa de root. Rode: sudo bash $0 $PAPEL"; exit 2
  fi
}

# TCP: devolve ABERTA (conectou), RECUSADA (host respondeu, porta fechada)
# ou FILTRADA (sem resposta = DROP do firewall OU host desligado).
tcp_estado() {
  timeout "$TIMEOUT" bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
  case $? in 0) echo ABERTA;; 124) echo FILTRADA;; *) echo RECUSADA;; esac
}
# liberado <descrição> <ip> <porta>  -> o firewall deve DEIXAR passar
liberado() {
  local e; e=$(tcp_estado "$2" "$3")
  case $e in
    ABERTA)   pass "$1 ($2:$3 aberta)";;
    RECUSADA) pass "$1 ($2:$3 alcançável; nenhum serviço escutando ainda)";;
    *)        fail "$1 ($2:$3 FILTRADA; esperado liberado)";;
  esac
}
# bloqueado <descrição> <ip> <porta>  -> o firewall deve DESCARTAR
bloqueado() {
  local e; e=$(tcp_estado "$2" "$3")
  if [ "$e" = FILTRADA ]; then pass "$1 ($2:$3 filtrada)"
  else fail "$1 ($2:$3 $e; esperado bloqueado)"; fi
}
ping_ok()   { if ping -c1 -W2 "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1 (sem resposta)"; fi; }
ping_bloq() { if ping -c1 -W2 "$2" >/dev/null 2>&1; then fail "$1 (respondeu; esperado bloqueado)"; else pass "$1"; fi; }
dns_ok() {
  local r; r=$(getent hosts "$1" | awk '{print $1; exit}')
  if [ "$r" = "$2" ]; then pass "DNS $1 -> $2"; else fail "DNS $1 (obtido: ${r:-nada}; esperado: $2)"; fi
}
servico_ativo() { # <unidade> [descrição]
  if systemctl is-active --quiet "$1"; then pass "${2:-$1} ativo"; else fail "${2:-$1} NÃO está ativo"; fi
}
servico_habilitado() {
  if systemctl is-enabled --quiet "$1" 2>/dev/null; then pass "$1 habilitado no boot"; else fail "$1 NÃO inicia no boot (systemctl enable $1)"; fi
}
# Endereços em escuta para uma porta TCP (coluna local do ss)
escuta() { ss -Hltn "( sport = :$1 )" 2>/dev/null | awk '{print $4}'; }

resumo() {
  secao "Resumo ($PAPEL, modo $MODO)"
  printf 'PASS=%d  FAIL=%d  AVISO=%d\n' "$PASS" "$FAIL" "$WARN"
  [ "$FAIL" -eq 0 ]
}

# Executa o corpo do teste e grava o log em ./resultados/
executar() {
  mkdir -p "$RESULT_DIR"
  local log="$RESULT_DIR/$NOME_TESTE-${PAPEL:-sempapel}-$(date +%Y%m%d-%H%M%S).log"
  principal 2>&1 | tee "$log"
  local rc=${PIPESTATUS[0]}
  echo "Log salvo em: $log"
  exit "$rc"
}

NOME_TESTE=conectividade
PAPEL=${1:-$(meu_papel)}

principal() {
  echo "Teste de CONECTIVIDADE - papel: ${PAPEL:-?}  modo: $MODO  ($(date '+%F %T'))"
  echo "Atenção: um resultado 'filtrada' também aparece se o DESTINO estiver desligado."
  echo "Rode primeiro 'roteador' para confirmar que todos os hosts respondem."

  case "$PAPEL" in
  roteador)
    secao "Roteador: os hosts de cada zona estão no ar?"
    ping_ok "Web (DMZ) responde"     "$WEB"
    ping_ok "Samba (LAN) responde"   "$FILES"
    ping_ok "Banco (DB) responde"    "$DB"
    ping_ok "Internet responde"      "$INTERNET"
    if ip route | grep -q '^default'; then pass "Rota default presente"; else fail "Sem rota default"; fi
    ;;

  cliente|samba)
    secao "Gateway e DNS (LAN)"
    ping_ok "Gateway $GW_LAN responde" "$GW_LAN"
    dns_ok "web.$DOMINIO"    "$WEB"
    dns_ok "db.$DOMINIO"     "$DB"
    dns_ok "files.$DOMINIO"  "$FILES"
    secao "LAN -> Web (DMZ)"
    liberado  "LAN acessa o Web em HTTP"   "$WEB" 80
    liberado  "LAN acessa o Web em HTTPS"  "$WEB" 443
    bloqueado "LAN NAO acessa SSH do Web"  "$WEB" 22
    bloqueado "LAN NAO acessa a API direto (8000)" "$WEB" 8000
    secao "LAN -> Banco (DB Zone)"
    bloqueado "LAN NAO acessa PostgreSQL"  "$DB" 5432
    bloqueado "LAN NAO acessa SSH do Banco" "$DB" 22
    ping_bloq "LAN NAO pinga o Banco"      "$DB"
    secao "LAN -> Internet e roteador"
    liberado  "LAN sai para a internet (443)" "$INTERNET" 443
    ping_ok   "LAN pinga a internet"       "$INTERNET"
    ping_ok   "LAN pinga o Web"            "$WEB"
    liberado  "LAN administra o roteador por SSH" "$GW_LAN" 22
    info "LAN -> internet:25 = $(tcp_estado "$INTERNET" 25). O README diz 'so 80/443'; a regra atual libera qualquer porta. DECISAO PENDENTE (Ysaac)."
    ;;

  web)
    secao "Gateway e DNS (DMZ)"
    ping_ok "Gateway $GW_DMZ responde" "$GW_DMZ"
    dns_ok "db.$DOMINIO" "$DB"
    secao "Web -> Banco"
    liberado  "Web acessa PostgreSQL"       "$DB" 5432
    bloqueado "Web NAO acessa SSH do Banco" "$DB" 22
    ping_bloq "Web NAO pinga o Banco (so 5432 e liberada)" "$DB"
    secao "Web -> LAN (deve ser isolado)"
    bloqueado "Web NAO acessa Samba (445)" "$FILES" 445
    bloqueado "Web NAO acessa Samba (139)" "$FILES" 139
    ping_bloq "Web NAO pinga a LAN"        "$FILES"
    secao "Web -> roteador e internet"
    bloqueado "DMZ NAO administra o roteador (SSH)" "$GW_DMZ" 22
    if [ "$MODO" = final ]; then
      bloqueado "Web sem internet (estado final)" "$INTERNET" 443
    else
      liberado  "Web com internet (modo dev: instalacao)" "$INTERNET" 443
    fi
    ;;

  banco)
    secao "Gateway e DNS (DB Zone)"
    ping_ok "Gateway $GW_DB responde" "$GW_DB"
    dns_ok "files.$DOMINIO" "$FILES"
    secao "Banco -> Samba (backups)"
    liberado  "Banco acessa Samba (445)"    "$FILES" 445
    liberado  "Banco acessa Samba (139)"    "$FILES" 139
    bloqueado "Banco NAO acessa SSH do Samba" "$FILES" 22
    ping_bloq "Banco NAO pinga o Samba"     "$FILES"
    secao "Banco -> demais zonas (deve ser isolado)"
    bloqueado "Banco NAO acessa o Web (80)" "$WEB" 80
    bloqueado "DB Zone NAO administra o roteador (SSH)" "$GW_DB" 22
    if [ "$MODO" = final ]; then
      bloqueado "Banco sem internet (estado final)" "$INTERNET" 443
    else
      liberado  "Banco com internet (modo dev: instalacao)" "$INTERNET" 443
    fi
    ;;

  *)
    echo "Papel nao identificado. Use: bash $0 {cliente|web|banco|samba|roteador}"
    return 2;;
  esac
  resumo
}
executar
