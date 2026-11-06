# Validação — InfraLab

> Responsável: Yahonan · Objetivo: provar que a infraestrutura funciona de forma integrada.
> Como usar: depois de montar as VMs, rodar os testes (ver `README.md`), preencher as colunas **Resultado** e **Evidência** e anexar os logs de `resultados/`.

## 1. Requisitos × testes

| ID | Requisito | Como é verificado | Resultado | Evidência |
|---|---|---|---|---|
| RF-01 | Rede segmentada em DMZ, LAN e DB Zone | `teste-conectividade.sh` em todos os papéis (matriz de acesso) | A executar | |
| RF-02 | Usuários da LAN acessam o site (porta 80) | conectividade `cliente`; servicos `cliente` (HTTP 200) | A executar | |
| RF-03 | A API grava e lê no PostgreSQL da DB Zone | servicos `web` (DATABASE_URL e conexão com `:5432`), servicos `cliente` (CRUD), servicos `banco` (conexão vinda do Web) | A executar | |
| RF-04 | Banco isolado da LAN e da internet | conectividade `cliente`/`banco`; seguranca `cliente` (varredura) | A executar | |
| RF-05 | Banco envia backup ao Samba (139/445) | conectividade `banco`; **cópia ainda não implementada** (ver B4) | A executar | |
| RF-06 | Backups automáticos e restauráveis | servicos `banco` e `samba`; procedimento de restore (seção 3) | A executar | |
| RF-07 | Serviços sobem sozinhos após reinício | `servico_habilitado` nos testes de serviços; reiniciar as VMs e repetir | A executar | |
| RF-08 | DNS e DHCP funcionam | conectividade (`dns_ok`); cliente recebe IP `.100–.200` (`ip a`) | A executar | |
| RF-09 | Samba separa acesso por grupo | procedimento manual (seção 3) | A executar | |
| RF-10 | Configuração segura (sem `trust`, API só em loopback, SMB1 desligado, políticas `drop`) | `teste-seguranca.sh` em todos os papéis | A executar | |
| RF-11 | Resiliência: banco cai e volta | procedimento manual (seção 3) | A executar | |

## 2. Achados já identificados

Origem: leitura do código dos cinco componentes e simulação em laboratório virtual (namespaces de rede Linux, PostgreSQL 16 e a API do Paulo). **Repetir nas VMs reais antes de registrar como validado.**

### Servidor Web (Paulo)

| ID | Gravidade | Achado | Detectado por |
|---|---|---|---|
| W1 | Alta | O `.env` nunca é lido: `config.py` usa `os.getenv` sem carregar o arquivo e a unit não tem `EnvironmentFile`. A API usa o padrão do código (SQLite em caminho inexistente) | servicos `web` |
| W2 | Alta | Com SQLite, `/health/ready` responde 200 "connected" sem PostgreSQL algum; os testes do repositório não tocam no PostgreSQL | servicos `web` (conexão `:5432`) |
| W3 | Alta | `postgresql://` com SQLAlchemy 2.1 procura o driver `psycopg` (v3), mas o requirements instala `psycopg2-binary`. Usar `postgresql+psycopg2://` | servicos `cliente` (CRUD) |
| W4 | Alta | `create_all` roda no import: com o banco fora do ar a API não sobe; `Restart=always` sem `RestartSec` pode esgotar o limite de reinícios do systemd | RF-11 (manual) |
| W5 | Alta | Scripts com variáveis vazias (`healthcheck.sh` sempre falha; `install.sh` e `backup-config.sh` quebrados); `install.sh` não cria usuário, não copia o projeto nem habilita o serviço | servicos `web` |
| W6 | Média | `DEBUG=True` por padrão, CORS `*`, `/docs` e `/openapi.json` públicos | seguranca `web` e `cliente` |
| W7 | Média | Sem HTTPS (Nginx só escuta a 80) | seguranca `cliente` (INFO) |
| W8 | Média | `/health/ready` só executa `SELECT 1`: não detecta falta de permissão na tabela | procedimento B1 (manual) |

### Banco de dados (Luiz)

| ID | Gravidade | Achado | Detectado por |
|---|---|---|---|
| B1 | Alta | Após `restaurar.sh` a tabela `items` passa a ser do `postgres` (`--no-owner`) e a API responde 500 `permission denied`, com `/health/ready` ainda 200. Correção testada: `pg_restore --role=infralab_user` | servicos `banco` (dono da tabela) |
| B2 | Alta | PostgreSQL escuta só em `localhost` e o `pg_hba.conf` não tem regra para o Web; nenhum script aplica o `postgresql.conf` | servicos `banco` |
| B3 | Média | Senha com `@`, `#`, `!` quebra a `DATABASE_URL` se não for codificada (URL-encode) | servicos `cliente` (CRUD) |
| B4 | Média | Backup só fica na própria VM; o caminho Banco→Samba existe no firewall, mas o `backup.sh` não copia | servicos `banco` (INFO) |

### Rede (Ysaac)

| ID | Gravidade | Achado | Detectado por |
|---|---|---|---|
| R1 | Alta | Regra TEMPORÁRIA: DMZ e DB acessam a internet na 443 (também recriada pelo `setup-router.sh`) | seguranca `roteador`; conectividade `web`/`banco` em modo `final` |
| R2 | Média | LAN sai para a internet em qualquer porta; o README diz "só 80/443" | seguranca `roteador` (AVISO); conectividade `cliente` (INFO) |
| R3 | Média | SSH do roteador aberto na interface WAN | seguranca `roteador` (AVISO) |
| R4 | Média | Não há configuração de rede (netplan/DNS) das VMs de servidor no repositório | conectividade (gateway e DNS) |
| R5 | Baixa | Não há acesso de administração aos servidores através do firewall (testes só pelo console) | — |
| R6 | Baixa | Arquivos vazios: `firewall.sh`, `interfaces.sh`, `configurar-rede.sh`, `roteamento.sh` | — |

### Servidor de arquivos (Rafael)

| ID | Gravidade | Achado | Detectado por |
|---|---|---|---|
| S1 | Alta | Nenhum usuário Samba (`smbpasswd -a`) é criado; `configurar-samba.sh` e `permissoes.sh` estão vazios | servicos `samba` |
| S2 | Média | `usr_adim` (scripts, grupos) × `usr_admin` (cotas): o usuário com cota pode não estar no `gpr_admin` | servicos `samba` (AVISO) |
| S3 | Média | Crontab com a linha duplicada e `backup-samba.sh` não instalado em `/usr/local/bin` | servicos `samba` |
| S4 | Média | Share `web` descrito como "HTML do servidor web", mas a DMZ não alcança a LAN | conectividade `web` |
| S5 | Média | Backup do banco não chega ao Samba (ver B4); falta definir o share (`dados` ou `backups`) e o usuário | servicos `samba` |
| S6 | Baixa | Sem `hosts allow`; cota de ~100 MB pode ser pequena para os dumps | seguranca `samba` (AVISO) |

### Geral

| ID | Gravidade | Achado |
|---|---|---|
| G1 | Média | Arquivos com final de linha CRLF quebram os scripts no Linux (`$'\r': command not found`). Conferir o Raw no GitHub e adicionar `.gitattributes` (`*.sh text eol=lf`) na raiz |
| G2 | Média | A regra temporária de internet precisa continuar ativa até as instalações (`apt`, `pip`) terminarem; só depois removê-la e validar em modo `final` |

## 3. Procedimentos manuais

**RF-09 — isolamento do Samba (no cliente):**
`smbclient //192.168.20.10/dados -U usr_web` → esperado `NT_STATUS_ACCESS_DENIED`;
`smbclient //192.168.20.10/web -U usr_web` → esperado: lista os arquivos.

**RF-06 — restore (numa VM de teste):** `sudo bash backups/restaurar.sh <arquivo.dump>` e depois um CRUD na API (`teste-servicos.sh cliente`) → esperado: tudo 200/201/204.

**RF-11 — resiliência:**
1. `sudo systemctl stop postgresql` no banco → `curl -i http://192.168.10.10/health/ready` → esperado 503.
2. `sudo systemctl start postgresql` → esperado 200 de novo, sem reiniciar a API.
3. Reiniciar o serviço da API com o banco desligado → registrar o comportamento (achado W4).

**RF-07 — reinício:** `sudo reboot` em cada VM, subir na ordem (roteador → banco → web → samba) e repetir os três scripts.

## 4. Registro de execução

| Data | VM / papel | Script | Modo | PASS | FAIL | AVISO | Log |
|---|---|---|---|---|---|---|---|
| | | | | | | | |

## 5. Critérios de aprovação

- Nenhum `[FAIL]` em modo `final` nos três scripts, em todos os papéis.
- Todo `[AVISO]` e `[INFO]` com decisão registrada (corrigir ou aceitar como limitação, com justificativa).
- Procedimentos manuais RF-06, RF-09 e RF-11 executados e anotados.

## 6. Limitações dos testes

- "Bloqueado" é inferido por falta de resposta: um destino desligado parece bloqueado. Rodar `roteador` antes.
- Os testes de bloqueio usam TCP e ping; UDP (DHCP/DNS) é verificado só por resolução de nomes e pela obtenção de IP.
- Samba: autenticação e acesso por grupo são manuais (dependem das senhas definidas pelo Rafael).
- HTTPS e autenticação da API estão fora do escopo atual.
