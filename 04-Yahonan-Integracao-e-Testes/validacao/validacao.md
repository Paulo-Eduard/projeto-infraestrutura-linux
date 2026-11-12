# Validação e Resultados (InfraLab)

**Objetivo:** registrar o cruzamento entre os requisitos do projeto e as evidências geradas pelos testes automatizados e pelos procedimentos manuais.

## 1. Registro de execução (cenário final)

- **Ambiente:** VMware Workstation, 4 VMs Ubuntu Server 24.04.5 LTS (`router-fw`, `web`, `banco`, `samba`).
- **Data:** 12/11/2026.
- **Modo:** `MODO=final`. A regra temporária de saída para a internet das zonas DMZ e DB foi **removida**.
- **Resultado geral:** nenhum `[FAIL]` em nenhuma VM.

| VM (papel) | Conectividade | Serviços | Segurança | Status |
|---|---|---|---|---|
| **Roteador** | 5 PASS · 0 FAIL · 0 AVISO | 8 · 0 · 0 | 6 · 0 · **2** | **APROVADO** |
| **Web** | 10 · 0 · 0 | 11 · 0 · 0 | 5 · 0 · 0 | **APROVADO** |
| **Banco** | 9 · 0 · 0 | 12 · 0 · 0 | 8 · 0 · 0 | **APROVADO** |
| **Samba** | 15 · 0 · 0 | 20 · 0 · 0 | 10 · 0 · 0 | **APROVADO** |
| **Cliente (LAN)** | — | 11 · 0 · 0 | ver observação | **APROVADO** |

Avisos do roteador (aceitos, ver seção 4): saída da LAN para a internet em qualquer porta na VM do laboratório e SSH do roteador aberto na WAN.

Observação (cliente): o teste de segurança do papel `cliente` registra os avisos de Nginx (versão no cabeçalho `Server` e `/docs` e `/openapi.json` públicos) enquanto o *hardening* opcional não for aplicado no `web`; são avisos, não falhas.

Logs originais: `resultados/logs-finais/<vm>/`.

## 2. Requisitos × evidências

As linhas citadas existem nos logs indicados.

| Requisito | Script / procedimento | Evidência (linha do log) |
|---|---|---|
| **Segmentação em 3 zonas** | `teste-conectividade.sh` (samba, web, banco) | `[PASS] LAN NAO acessa PostgreSQL (192.168.30.10:5432 filtrada)` · `[PASS] Web NAO acessa Samba (445)` · `[PASS] Banco NAO acessa o Web (80)` |
| **Web alcança o banco só na 5432** | `teste-conectividade.sh web` | `[PASS] Web acessa PostgreSQL (192.168.30.10:5432 aberta)` · `[PASS] Web NAO acessa SSH do Banco` |
| **Integração Aplicação ↔ Banco** | `teste-servicos.sh web` e `cliente` | `[PASS] DATABASE_URL usa PostgreSQL (postgresql+psycopg2://...@192.168.30.10:5432/infralab_db)` · `[PASS] Conexao TCP estabelecida com 192.168.30.10:5432` · `[PASS] POST criou o item (HTTP 201)` |
| **CRUD completo pelo usuário (LAN → Nginx → API → banco)** | `teste-servicos.sh cliente` | `POST 201`, `GET 200`, `PUT 200`, `DELETE 204`, `GET após DELETE 404` |
| **Banco isolado da LAN** | `teste-conectividade.sh samba` e `teste-seguranca.sh cliente` | `[PASS] Banco totalmente inacessivel a partir da LAN` |
| **Isolamento de internet (Web e Banco)** | `teste-conectividade.sh web` e `banco` (modo final) | `[PASS] Web sem internet (estado final) (8.8.8.8:443 filtrada)` · `[PASS] Banco sem internet (estado final)` |
| **Regra temporária removida** | `teste-seguranca.sh roteador` | `[PASS] Regra temporaria de internet removida (DMZ e DB isoladas)` |
| **Backup automático, válido e com cópia externa** | `teste-servicos.sh banco` | `[PASS] Cron do postgres tem o backup agendado` · `[PASS] Backup legivel (pg_restore --list)` · cópia no Samba: `[PASS] Copia do backup presente no Samba (//192.168.20.10/dados)` |
| **Restore preservando o dono da tabela** | procedimento manual (`restaurar.sh`) + `teste-servicos.sh cliente` | CRUD completo (11 PASS) depois do restore, sem `permission denied` |
| **Controle de acesso do Samba por grupo** | procedimento manual (`smbclient`) | `usr_dados` lista `//…/dados`; `usr_web` recebe `NT_STATUS_ACCESS_DENIED` |
| **Samba configurado com segurança** | `teste-seguranca.sh samba` | `[PASS] map to guest = Never` · `[PASS] Protocolo minimo SMB2 (SMB1 desativado)` · `[PASS] hosts allow definido` |
| **Banco configurado com segurança** | `teste-seguranca.sh banco` | `[PASS] pg_hba.conf sem metodo 'trust'` · `[PASS] listen_addresses restrito (localhost,192.168.30.10)` · `[PASS] Senhas com scram-sha-256` |
| **API exposta só pelo Nginx** | `teste-seguranca.sh web` | `[PASS] API (8000) escuta apenas em 127.0.0.1` · `[PASS] Servico infralab-api roda como usuario 'infralab'` |
| **Resiliência: banco cai e volta** | procedimento manual | `/health/ready` → **HTTP 503** (`"database":"disconnected"`) com o banco parado e **HTTP 200** (`"connected"`) depois, sem reiniciar a API |
| **Serviços sobem no boot** | `servico_habilitado` nos testes de serviços | `[PASS] nginx habilitado no boot` · `[PASS] postgresql habilitado no boot` · `[PASS] smbd habilitado no boot` · `[PASS] nftables habilitado no boot` |

## 3. Achados identificados durante a integração e status

| Componente | Achado | Status |
|---|---|---|
| Web | `.env` não era carregado; scripts com variáveis vazias; sem `RestartSec` | **Corrigido** no repositório (`EnvironmentFile`, `RestartSec`, `install.sh`, `healthcheck.sh`) |
| Web | API caía em SQLite sem avisar; driver `psycopg2` exige `postgresql+psycopg2://`; `DEBUG=True` | **Corrigido** no ambiente (`DATABASE_URL` e `DEBUG=False`); teste confirma conexão TCP real |
| Banco | `restaurar.sh` deixava a tabela com dono `postgres` | **Corrigido** (`--role=infralab_user`) |
| Banco | Escutava só em `localhost` e sem regra no `pg_hba.conf` | **Corrigido** no ambiente (`listen_addresses` e linha do Web) |
| Banco | `backup.sh` e `instalar.sh` com cercas markdown (`` ``` ``) quebravam a execução | **Corrigido** no repositório |
| Banco | Backup só local | **Corrigido**: `backup.sh` envia ao Samba (share `dados`) |
| Rede | Regra temporária de internet para DMZ e DB | **Removida** (teste em modo final) |
| Rede | Saída da LAN em qualquer porta (README dizia 80/443) | **Corrigido no repositório**; roteador do laboratório mantém a regra antiga → **aviso aceito** |
| Rede | SSH do roteador aberto na WAN | **Aceito** (administração remota do laboratório) |
| Rede | Servidores sem `netplan` no repositório | **Documentado** em `integracao.md` (seção 7) |
| Samba | Usuário admin com nome diferente nos scripts; crontab com linha duplicada | **Corrigido** pelo Rafael |
| Samba | Nenhum usuário com senha Samba | **Corrigido** no ambiente (`smbpasswd -a`) |
| Samba | `configurar-samba.sh`, `permissoes.sh` e `compartilhamentos.md` vazios | **Pendência menor** (a configuração foi aplicada manualmente e está descrita aqui) |
| Samba | `hosts allow` ausente do `smb.conf` do repositório | **Aplicado no ambiente**; falta incluir no repositório |
| Samba | Share `web` descrito como "HTML do servidor web", mas a DMZ não alcança a LAN | **Limitação documentada** (acesso só pela LAN) |
| Geral | Final de linha CRLF quebra scripts no Linux | **Mitigado** com `.gitattributes` (`*.sh text eol=lf`) |
| Web | Versão do Nginx, `/docs` e `/openapi.json` públicos; sem HTTPS | **Aviso aceito** (HTTPS e autenticação fora do escopo) |

## 4. Decisões aceitas pela equipe

1. **SSH do roteador na interface WAN:** mantido para administração remota; em produção seria restringido por origem.
2. **Saída da LAN em qualquer porta (roteador do laboratório):** o repositório já restringe a 80/443; a VM usa a cópia anterior.
3. **Cabeçalhos do Nginx, Swagger público e ausência de HTTPS:** aceitos para o escopo acadêmico.
4. **Teste de bloqueio por ausência de resposta:** um destino desligado também parece "filtrado"; por isso o papel `roteador` é executado primeiro para confirmar que todos os hosts respondem.

## 5. Critérios de conclusão

1. Nenhum `[FAIL]` nos logs da versão de entrega (`MODO=final`) em todas as VMs. **Atendido.**
2. A aplicação consome o PostgreSQL da DB Zone sem que o banco esteja exposto à LAN. **Atendido.**
3. Web e Banco sem acesso à internet; o Web não alcança a LAN. **Atendido.**
4. Backup válido, com cópia no Samba, e restore que preserva a aplicação. **Atendido.**
5. Todo `[AVISO]` tem decisão registrada (seção 4). **Atendido.**
6. Evidências salvas em `resultados/`. **Atendido** quando os logs das 4 VMs forem enviados ao repositório.
