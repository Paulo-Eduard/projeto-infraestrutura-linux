#!/usr/bin/env bash
# teste-servicos.sh
# Verifica servicos, portas, integracao Web-Banco, backups e o fluxo completo (CRUD).
#
# Uso:  sudo bash teste-servicos.sh [cliente|web|banco|samba|roteador]
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

NOME_TESTE=servicos
PAPEL=${1:-$(meu_papel)}
API_UNIT=${API_UNIT:-infralab-api}
BKP_DB_DIR=${BKP_DB_DIR:-/var/backups/infralab/postgresql}
BKP_SMB_DIR=${BKP_SMB_DIR:-/srv/backups}

http_code() { curl -s -o /dev/null -m 5 -w '%{http_code}' "$@" 2>/dev/null; }
checa_http() { # <descrição> <esperado> <url> [args do curl]
  local d=$1 esp=$2; shift 2
  local c; c=$(http_code "$@")
  if [ "$c" = "$esp" ]; then pass "$d (HTTP $c)"; else fail "$d (HTTP ${c:-000}; esperado $esp)"; fi
}
psql_pg() { runuser -u postgres -- psql -d "${2:-postgres}" -tAc "$1" 2>/dev/null; }
env_da_api() { # caminho do EnvironmentFile da unit (vazio se não houver)
  systemctl show "$API_UNIT" -p EnvironmentFiles --value 2>/dev/null | awk '{print $1}' | sed 's/^-//'
}

principal() {
  echo "Teste de SERVICOS - papel: ${PAPEL:-?}  ($(date '+%F %T'))"
  case "$PAPEL" in

  cliente)
    secao "Fluxo completo visto pelo usuario: LAN -> Nginx -> API -> Banco"
    local base="http://$WEB"
    checa_http "Pagina inicial da API"        200 "$base/"
    checa_http "/health"                      200 "$base/health"
    checa_http "/health/ready (API enxerga o banco)" 200 "$base/health/ready"
    if curl -s -m 5 "$base/health/ready" | grep -q 'connected'; then pass "/health/ready informa database=connected"
    else fail "/health/ready nao informa database=connected"; fi
    checa_http "Listagem /api/v1/items"       200 "$base/api/v1/items"
    local c; c=$(http_code "$base/app/")
    if [ "$c" = 200 ]; then pass "Frontend /app/ (HTTP 200)"; else warn "Frontend /app/ retornou HTTP ${c:-000} (confirmar com o Paulo)"; fi

    secao "CRUD completo (grava e le no PostgreSQL)"
    local titulo="teste-integracao-$(date +%s)" resp id
    resp=$(curl -s -m 8 -X POST "$base/api/v1/items" -H 'Content-Type: application/json' \
           -d "{\"title\":\"$titulo\",\"price\":9.9}" -w '\n%{http_code}')
    if [ "$(tail -n1 <<<"$resp")" = 201 ]; then pass "POST criou o item (HTTP 201)"; else fail "POST (HTTP $(tail -n1 <<<"$resp"))"; fi
    id=$(head -n1 <<<"$resp" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
    if [ -n "$id" ]; then
      checa_http "GET do item $id"            200 "$base/api/v1/items/$id"
      checa_http "PUT do item $id"            200 -X PUT "$base/api/v1/items/$id" -H 'Content-Type: application/json' -d '{"price":12.5}'
      checa_http "DELETE do item $id"         204 -X DELETE "$base/api/v1/items/$id"
      checa_http "GET apos DELETE (some)"     404 "$base/api/v1/items/$id"
    else
      fail "Nao foi possivel obter o id do item criado; CRUD interrompido"
    fi
    secao "Samba (visto pelo cliente)"
    if command -v smbclient >/dev/null; then
      info "Teste manual de autenticacao: smbclient -L //$FILES -U usr_dados"
      info "Esperado: lista web, dados, publica, backups conforme o grupo do usuario."
    else
      info "smbclient nao instalado (sudo apt install smbclient) - teste do Samba pendente"
    fi
    ;;

  web)
    precisa_root
    secao "Servicos do servidor Web"
    servico_ativo nginx "Nginx"
    servico_ativo "$API_UNIT" "API ($API_UNIT)"
    servico_habilitado nginx
    servico_habilitado "$API_UNIT"
    if nginx -t 2>&1 | grep -q 'successful'; then pass "nginx -t: configuracao valida"; else fail "nginx -t acusou erro"; fi
    secao "Portas"
    if escuta 80 | grep -q .; then pass "Porta 80 em escuta"; else fail "Porta 80 sem servico"; fi
    if escuta 8000 | grep -q .; then pass "API em escuta na 8000"; else fail "API nao escuta na 8000"; fi
    secao "Respostas locais"
    checa_http "/health (via Nginx)"        200 http://127.0.0.1/health
    checa_http "/health/ready (via Nginx)"  200 http://127.0.0.1/health/ready
    secao "A API usa o PostgreSQL de verdade (nao SQLite)?"
    local envf; envf=$(env_da_api)
    if [ -n "$envf" ] && [ -r "$envf" ]; then
      local url; url=$(grep -E '^DATABASE_URL=' "$envf" | head -1 | cut -d= -f2-)
      case "$url" in
        postgresql*) pass "DATABASE_URL usa PostgreSQL ($(sed -E 's#(://[^:]+):[^@]*@#\1:***@#' <<<"$url"))";;
        sqlite*)     fail "DATABASE_URL aponta para SQLite";;
        *)           fail "DATABASE_URL ausente ou inesperada em $envf";;
      esac
      if grep -qE "@(localhost|127\.0\.0\.1)" <<<"$url"; then warn "DATABASE_URL aponta para localhost; a arquitetura pede o IP da DB Zone ($DB)"; fi
    else
      fail "A unit $API_UNIT nao tem EnvironmentFile legivel (o .env nunca e carregado) - ver validacao.md, achado W1"
    fi
    curl -s -m 5 http://127.0.0.1/health/ready >/dev/null
    if ss -Htn state established "( dport = :5432 )" 2>/dev/null | grep -q "$DB"; then pass "Conexao TCP estabelecida com $DB:5432"
    else fail "Nenhuma conexao estabelecida com $DB:5432 (API nao fala com o Postgres da DB Zone)"; fi
    ;;

  banco)
    precisa_root
    secao "Servico PostgreSQL"
    servico_ativo postgresql "PostgreSQL"
    servico_habilitado postgresql
    secao "Rede"
    local ends; ends=$(escuta 5432)
    if grep -qE "^($DB|0\.0\.0\.0|\*|\[::\]):" <<<"$ends"; then pass "PostgreSQL escuta em $DB (acessivel pela rede)"
    else fail "PostgreSQL escuta so em: ${ends:-nada}; o Web (DMZ) nao conseguira conectar (listen_addresses)"; fi
    local hba; hba=$(psql_pg "show hba_file")
    if [ -n "$hba" ] && awk -v w="$WEB/32" '$1=="host" && $2=="infralab_db" && $3=="infralab_user" && ($4==w || $4=="192.168.10.0/24")' "$hba" | grep -q .; then
      pass "pg_hba.conf libera infralab_user a partir do Web ($WEB)"
    else fail "pg_hba.conf sem regra para infralab_user vindo de $WEB"; fi
    if ss -Htn state established "( sport = :5432 )" 2>/dev/null | grep -q "$WEB"; then pass "Ha conexao ativa vinda do Web ($WEB)"
    else warn "Nenhuma conexao ativa do Web agora (faca uma requisicao na API e repita)"; fi
    secao "Banco, usuario e tabela"
    [ "$(psql_pg "select 1 from pg_database where datname='infralab_db'")" = 1 ] && pass "Banco infralab_db existe" || fail "Banco infralab_db nao existe"
    [ "$(psql_pg "select rolsuper from pg_roles where rolname='infralab_user'")" = f ] && pass "infralab_user existe e nao e superusuario" || fail "infralab_user ausente ou superusuario"
    local dono; dono=$(psql_pg "select tableowner from pg_tables where tablename='items'" infralab_db)
    if [ "$dono" = infralab_user ]; then pass "Tabela items existe e pertence a infralab_user"
    elif [ -z "$dono" ]; then warn "Tabela items ainda nao existe (sera criada na 1a subida da API)"
    else fail "Tabela items pertence a '$dono' (a API recebera 'permission denied'; tipico apos restore com --no-owner)"; fi
    secao "Backup"
    if crontab -u postgres -l 2>/dev/null | grep -q 'infralab-backup'; then pass "Cron do postgres tem o backup agendado"; else fail "Backup nao agendado no cron do postgres"; fi
    local ult; ult=$(ls -1t "$BKP_DB_DIR"/*.dump 2>/dev/null | head -1)
    if [ -n "$ult" ]; then
      pass "Ultimo backup: $(basename "$ult")"
      if [ -n "$(find "$ult" -mmin -1560)" ]; then pass "Backup com menos de 26h"; else warn "Ultimo backup tem mais de 26h"; fi
      if runuser -u postgres -- pg_restore --list "$ult" >/dev/null 2>&1; then pass "Backup legivel (pg_restore --list)"; else fail "Backup corrompido"; fi
    else fail "Nenhum .dump em $BKP_DB_DIR (rode: sudo bash backups/backup.sh)"; fi
    info "Copia do backup para o Samba: nao implementada no backup.sh (pendencia Luiz + Rafael)."
    ;;

  samba)
    precisa_root
    secao "Servico Samba"
    servico_ativo smbd "Samba (smbd)"
    servico_habilitado smbd
    escuta 445 | grep -q . && pass "Porta 445 em escuta" || fail "Porta 445 sem servico"
    escuta 139 | grep -q . && pass "Porta 139 em escuta" || fail "Porta 139 sem servico"
    secao "Configuracao"
    if testparm -s >/dev/null 2>&1; then pass "testparm: smb.conf valido"; else fail "testparm acusou erro"; fi
    local s; for s in web dados publica backups; do
      testparm -s 2>/dev/null | grep -q "^\[$s\]" && pass "Share [$s] definido" || fail "Share [$s] ausente"
    done
    secao "Diretorios (dono do grupo e modo)"
    local par d g
    for par in /srv/samba/web:gpr_web /srv/samba/dados:gpr_dados /srv/samba/publica:gpr_todos /srv/backups:gpr_admin; do
      d=${par%%:*}; g=${par##*:}
      if [ -d "$d" ]; then
        [ "$(stat -c '%G' "$d")" = "$g" ] && pass "$d pertence ao grupo $g" || fail "$d com grupo $(stat -c '%G' "$d") (esperado $g)"
      else fail "$d nao existe"; fi
    done
    secao "Usuarios"
    local u; for u in usr_web usr_dados; do id "$u" >/dev/null 2>&1 && pass "Usuario $u existe" || fail "Usuario $u ausente"; done
    if id usr_admin >/dev/null 2>&1 && id usr_adim >/dev/null 2>&1; then warn "Existem usr_admin E usr_adim (erro de digitacao nos scripts do Rafael)"
    elif id usr_admin >/dev/null 2>&1 || id usr_adim >/dev/null 2>&1; then pass "Usuario admin existe"; else fail "Usuario admin ausente"; fi
    local n; n=$(pdbedit -L 2>/dev/null | wc -l)
    if [ "$n" -gt 0 ]; then pass "$n usuario(s) cadastrado(s) no Samba (smbpasswd -a)"; else fail "Nenhum usuario no Samba: ninguem consegue autenticar (smbpasswd -a)"; fi
    secao "Backup"
    local cr; cr=$(crontab -l 2>/dev/null | grep -c 'backup-samba')
    case "$cr" in 1) pass "Backup agendado uma vez no cron do root";; 0) fail "Backup nao agendado no cron do root";; *) warn "Backup agendado $cr vezes no cron (linha duplicada)";; esac
    [ -x /usr/local/bin/backup-samba.sh ] && pass "/usr/local/bin/backup-samba.sh instalado" || fail "/usr/local/bin/backup-samba.sh ausente"
    local ub; ub=$(ls -1t "$BKP_SMB_DIR"/samba_*.tar.gz 2>/dev/null | head -1)
    [ -n "$ub" ] && pass "Ultimo backup: $(basename "$ub")" || fail "Nenhum samba_*.tar.gz em $BKP_SMB_DIR"
    ;;

  roteador)
    precisa_root
    secao "Servicos do roteador"
    servico_ativo nftables "nftables"
    servico_habilitado nftables
    servico_ativo dnsmasq "dnsmasq (DNS/DHCP)"
    servico_habilitado dnsmasq
    [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" = 1 ] && pass "net.ipv4.ip_forward = 1" || fail "Encaminhamento de pacotes desligado"
    [ -f /etc/nftables.conf ] && pass "/etc/nftables.conf presente (regras persistem no boot)" || fail "/etc/nftables.conf ausente"
    [ "$(nft list ruleset 2>/dev/null | grep -c 'policy drop')" -ge 2 ] && pass "Politica drop em input e forward" || fail "Politica drop ausente"
    nft list ruleset 2>/dev/null | grep -q masquerade && pass "NAT (masquerade) ativo" || fail "NAT ausente"
    ;;

  *)
    echo "Papel nao identificado. Use: bash $0 {cliente|web|banco|samba|roteador}"
    return 2;;
  esac
  resumo
}
executar
