#!/usr/bin/env bash
# teste-seguranca.sh
# Verifica exposicao de portas, configuracoes seguras e regras que ainda precisam de decisao.
#
# Uso:  sudo bash teste-seguranca.sh [cliente|web|banco|samba|roteador]
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

NOME_TESTE=seguranca
PAPEL=${1:-$(meu_papel)}
BKP_DB_DIR=${BKP_DB_DIR:-/var/backups/infralab/postgresql}
API_UNIT=${API_UNIT:-infralab-api}
PORTAS_COMUNS="21 22 23 25 53 80 110 139 443 445 3306 3389 5432 8000 8080 8443"

psql_pg() { runuser -u postgres -- psql -d "${2:-postgres}" -tAc "$1" 2>/dev/null; }

# varredura <ip> -> imprime as portas comuns que NÃO estão filtradas (em paralelo)
varredura() {
  local ip=$1 tmp p; tmp=$(mktemp -d)
  for p in $PORTAS_COMUNS; do
    ( [ "$(TIMEOUT=1 tcp_estado "$ip" "$p")" != FILTRADA ] && echo "$p" > "$tmp/$p" ) &
  done
  wait
  ls "$tmp" 2>/dev/null | sort -n | tr '\n' ' '
  rm -rf "$tmp"
}

ssh_basico() {
  secao "SSH desta VM"
  if command -v sshd >/dev/null 2>&1; then
    local r; r=$(sshd -T 2>/dev/null | awk '/^permitrootlogin/ {print $2}')
    case "$r" in
      no|prohibit-password|without-password) pass "Login SSH direto como root restrito ($r)";;
      yes) fail "PermitRootLogin yes";;
      *)   info "Nao foi possivel ler a configuracao do sshd (rode com sudo)";;
    esac
  else info "sshd nao instalado nesta VM"; fi
}

principal() {
  echo "Teste de SEGURANCA - papel: ${PAPEL:-?}  modo: $MODO  ($(date '+%F %T'))"
  case "$PAPEL" in

  cliente)
    secao "Exposicao vista da LAN (portas comuns nao filtradas)"
    local ab
    ab=$(varredura "$WEB"); ab=${ab% }
    info "Web ($WEB): portas alcancaveis = ${ab:-nenhuma}"
    if [ -z "$(tr ' ' '\n' <<<"$ab" | grep -vxE '80|443|')" ]; then pass "Web expoe apenas 80/443 para a LAN"
    else fail "Web expoe portas alem de 80/443: $ab"; fi
    ab=$(varredura "$DB"); ab=${ab% }
    info "Banco ($DB): portas alcancaveis = ${ab:-nenhuma}"
    [ -z "$ab" ] && pass "Banco totalmente inacessivel a partir da LAN" || fail "Banco expoe portas para a LAN: $ab"
    ab=$(varredura "$GW_DMZ"); ab=${ab% }
    info "Roteador pelo lado DMZ ($GW_DMZ), visto da LAN: ${ab:-nenhuma}"
    secao "Cabecalhos e rotas expostas no Web"
    local srv; srv=$(curl -sI -m 5 "http://$WEB/" | tr -d '\r' | awk -F': ' 'tolower($1)=="server"{print $2}')
    if grep -q '/' <<<"$srv"; then warn "Cabecalho Server revela a versao: $srv (server_tokens off)"; else pass "Versao do servidor nao revelada (${srv:-sem cabecalho})"; fi
    local c
    c=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$WEB/docs"); [ "$c" = 200 ] && warn "/docs (Swagger) publico via Nginx" || pass "/docs nao publico (HTTP $c)"
    c=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$WEB/openapi.json"); [ "$c" = 200 ] && warn "/openapi.json publico via Nginx" || pass "/openapi.json nao publico (HTTP $c)"
    c=$(curl -s -m 5 -X POST "http://$WEB/api/v1/items" -H 'Content-Type: application/json' -d '{"title":"","price":-1}' -o /dev/null -w '%{http_code}')
    [ "$c" = 422 ] && pass "Entrada invalida rejeitada (HTTP 422)" || warn "Entrada invalida retornou HTTP $c (esperado 422)"
    info "Faltam (fora do escopo atual): HTTPS no Nginx (so porta 80) e autenticacao na API."
    ;;

  web)
    precisa_root
    ssh_basico
    secao "Superficie da API"
    local ends; ends=$(escuta 8000)
    if [ -z "$ends" ]; then fail "Nada escuta na 8000 (API fora do ar)"
    elif grep -vE '^(127\.0\.0\.1|\[::1\]):' <<<"$ends" | grep -q .; then fail "API escuta fora do loopback ($(tr '\n' ' ' <<<"$ends")); so o Nginx deveria ser publico"
    else pass "API (8000) escuta apenas em 127.0.0.1"; fi
    secao "Processo e segredos"
    local u; u=$(systemctl show "$API_UNIT" -p User --value 2>/dev/null)
    case "$u" in ""|root) fail "Servico $API_UNIT roda como root (${u:-vazio = root})";; *) pass "Servico $API_UNIT roda como usuario '$u'";; esac
    local f bad=0
    while IFS= read -r f; do
      [ -n "$f" ] && { fail "Arquivo de segredos legivel por todos: $f"; bad=1; }
    done < <(find /opt/infralab -name '.env' -perm /o+r 2>/dev/null)
    [ "$bad" = 0 ] && pass "Nenhum .env legivel por 'outros' em /opt/infralab"
    if grep -rEqi '^DEBUG=(true|1)' /opt/infralab --include=.env 2>/dev/null; then warn "DEBUG ativo no .env (erros 500 revelam detalhes internos)"; else pass "DEBUG nao esta ativo no .env"; fi
    ;;

  banco)
    precisa_root
    ssh_basico
    secao "Exposicao e autenticacao"
    local la; la=$(psql_pg "show listen_addresses")
    if grep -q '\*' <<<"$la"; then fail "listen_addresses='$la' (escuta em todas as interfaces)"; else pass "listen_addresses restrito ($la)"; fi
    local hba; hba=$(psql_pg "show hba_file")
    if [ -n "$hba" ]; then
      if grep -vE '^\s*#' "$hba" | grep -qwi 'trust'; then fail "pg_hba.conf contem metodo 'trust'"; else pass "pg_hba.conf sem metodo 'trust'"; fi
      if grep -vE '^\s*#' "$hba" | grep -q '0\.0\.0\.0/0'; then fail "pg_hba.conf libera 0.0.0.0/0"; else pass "pg_hba.conf sem 0.0.0.0/0"; fi
    else fail "Nao foi possivel localizar o pg_hba.conf"; fi
    [ "$(psql_pg "show password_encryption")" = scram-sha-256 ] && pass "Senhas com scram-sha-256" || warn "password_encryption diferente de scram-sha-256"
    [ "$(psql_pg "select rolsuper from pg_roles where rolname='infralab_user'")" = f ] && pass "infralab_user nao e superusuario" || fail "infralab_user e superusuario ou nao existe"
    secao "Backups"
    if [ -d "$BKP_DB_DIR" ]; then
      if [ -z "$(find "$BKP_DB_DIR" -type f -perm /o+r 2>/dev/null)" ]; then pass "Backups nao legiveis por 'outros'"; else fail "Ha backups legiveis por 'outros' em $BKP_DB_DIR"; fi
      case "$(stat -c '%a' "$BKP_DB_DIR")" in 700|750) pass "Diretorio de backup com modo $(stat -c '%a' "$BKP_DB_DIR")";; *) warn "Diretorio de backup com modo $(stat -c '%a' "$BKP_DB_DIR")";; esac
    else warn "$BKP_DB_DIR nao existe"; fi
    info "Backups ficam so nesta VM (sem copia externa): risco registrado em validacao.md."
    ;;

  samba)
    precisa_root
    ssh_basico
    secao "Configuracao do Samba"
    local cfg; cfg=$(testparm -sv 2>/dev/null)
    if [ -z "$cfg" ]; then fail "testparm nao retornou configuracao"; else
      grep -qiE 'guest ok = yes' <<<"$cfg" && fail "Existe share com guest ok = yes" || pass "Nenhum share permite convidado"
      grep -qiE 'map to guest = never' <<<"$cfg" && pass "map to guest = Never" || warn "map to guest diferente de Never"
      local mp; mp=$(awk -F= '/server min protocol/ {gsub(/ /,"",$2); print $2; exit}' <<<"$cfg")
      case "$mp" in SMB2*|SMB3*) pass "Protocolo minimo $mp (SMB1 desativado)";; *) fail "server min protocol = ${mp:-?} (SMB1 habilitado)";; esac
      grep -qiE 'null passwords = yes' <<<"$cfg" && fail "Senhas vazias permitidas" || pass "Senhas vazias nao permitidas"
      if awk -F= '/^[[:space:]]*hosts allow/ {gsub(/[[:space:]]/,"",$2); if ($2!="") f=1} END{exit !f}' <<<"$cfg"; then pass "hosts allow definido"
      else warn "Sem 'hosts allow': recomendado 192.168.20.0/24 e $DB"; fi
    fi
    secao "Permissoes dos diretorios"
    local d m
    for d in /srv/samba/web /srv/samba/dados /srv/samba/publica /srv/backups; do
      if [ -d "$d" ]; then m=$(stat -c '%a' "$d")
        case "$m" in *0) pass "$d modo $m (sem acesso para 'outros')";; *) fail "$d modo $m (acessivel por 'outros')";; esac
      else fail "$d nao existe"; fi
    done
    secao "Teste de isolamento entre grupos (manual)"
    info "Com usr_web: smbclient //$FILES/dados -U usr_web  -> esperado NT_STATUS_ACCESS_DENIED"
    info "Com usr_dados: smbclient //$FILES/backups -U usr_dados -> esperado NT_STATUS_ACCESS_DENIED"
    ;;

  roteador)
    precisa_root
    ssh_basico
    secao "Politica do firewall"
    nft list chain inet filter input   2>/dev/null | grep -q 'policy drop' && pass "Chain input com policy drop"   || fail "Chain input sem policy drop"
    nft list chain inet filter forward 2>/dev/null | grep -q 'policy drop' && pass "Chain forward com policy drop" || fail "Chain forward sem policy drop"
    nft list chain inet filter forward 2>/dev/null | grep -q 'ct state invalid drop' && pass "Pacotes invalidos descartados" || warn "Sem descarte de ct state invalid"
    nft list chain inet filter forward 2>/dev/null | grep -q 'log prefix' && pass "Descartes registrados em log" || warn "Sem log de descartes"
    secao "Regras que precisam de decisao ou remocao"
    local fw; fw=$(nft list chain inet filter forward 2>/dev/null)
    if grep -qE "oifname \"$WAN_IF\" tcp dport \{ 80, 443 \}" <<<"$fw"; then
      if [ "$MODO" = final ]; then fail "Regra TEMPORARIA ativa: DMZ/DB acessam a internet (remover do nftables.conf E do setup-router.sh)"
      else warn "Regra temporaria de internet ativa (aceitavel no modo dev; remover antes da entrega)"; fi
    else pass "Regra temporaria de internet removida (DMZ e DB isoladas)"; fi
    grep -qE "iifname \"$LAN_IF\" oifname \"$WAN_IF\" accept" <<<"$fw" && warn "LAN sai para a internet em QUALQUER porta (README diz so 80/443)" || pass "Saida da LAN restrita"
    nft list chain inet filter input 2>/dev/null | grep -qE "iifname \"$WAN_IF\" tcp dport 22 accept" && warn "SSH do roteador aberto na interface WAN" || pass "SSH nao aberto na WAN"
    ;;

  *)
    echo "Papel nao identificado. Use: bash $0 {cliente|web|banco|samba|roteador}"
    return 2;;
  esac
  resumo
}
executar
