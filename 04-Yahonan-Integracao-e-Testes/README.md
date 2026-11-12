# 04 — Integração e Testes (Yahonan)

**Objetivo:** garantir o funcionamento integrado da infraestrutura InfraLab (DMZ, LAN e DB Zone) e provar isso com testes repetíveis.

**Resultado:** 4 VMs aprovadas em `MODO=final`, sem nenhum `[FAIL]`. Detalhes e evidências em [`validacao/validacao.md`](validacao/validacao.md).

## O que tem aqui

| Pasta / arquivo | Para quê |
|---|---|
| [`integracao/integracao.md`](integracao/integracao.md) | Topologia, endereçamento, matriz de acesso do firewall, fluxos, ordem de montagem no VMware e configurações que ligam os componentes |
| [`testes/conectividade/teste-conectividade.sh`](testes/conectividade/teste-conectividade.sh) | Gateway, DNS e matriz de acesso (o que o firewall deve liberar e bloquear) |
| [`testes/servicos/teste-servicos.sh`](testes/servicos/teste-servicos.sh) | Serviços, portas, ligação Web ↔ Banco, backups (inclui a cópia no Samba) e CRUD completo pela LAN |
| [`testes/seguranca/teste-seguranca.sh`](testes/seguranca/teste-seguranca.sh) | Exposição de portas e configurações seguras de cada componente |
| [`validacao/validacao.md`](validacao/validacao.md) | Resultados, requisitos × evidências, achados e decisões aceitas |
| `resultados/` | Logs gerados pelos scripts (evidências) |

## Como rodar os testes

Execute **no console ou no SSH de cada VM** (o firewall não deixa a LAN entrar por SSH no Web e no Banco):

```bash
cd ~/projeto-infraestrutura-linux/04-Yahonan-Integracao-e-Testes
sudo -v                                  # autentica o sudo uma vez
sudo bash testes/conectividade/teste-conectividade.sh [papel]
sudo bash testes/servicos/teste-servicos.sh [papel]
sudo bash testes/seguranca/teste-seguranca.sh [papel]
```

- **Papéis:** `roteador`, `banco`, `web`, `samba`, `cliente`. Sem argumento, o papel é detectado pelo IP da VM. O papel `cliente` roda de qualquer VM da LAN, sem `sudo`.
- **Modos:** `MODO=final` (padrão, estado de entrega) ou `MODO=dev` (durante a instalação, quando a regra temporária de internet ainda existe).
- **Roteador:** informe os nomes das interfaces do laboratório: `sudo WAN_IF=ens32 LAN_IF=ens34 bash ...`.
- **Saída:** `[PASS]`, `[FAIL]`, `[AVISO]` (decisão registrada) e `[INFO]`; o log vai para `resultados/`; o código de saída é diferente de zero se houver `[FAIL]`.
- **Endereços diferentes?** Sobrescreva por variável de ambiente, por exemplo `WEB=192.168.10.20 sudo -E bash ...`.

Resumo rápido dos resultados de uma VM:

```bash
grep -hE '^\[(FAIL|AVISO)\]|^PASS=' resultados/*.log
```

## Roteiro de demonstração (~10 minutos)

**Antes de começar**
1. Ligue as VMs na ordem `router-fw` → `banco` → `web` → `samba` e aguarde cerca de 2 minutos.
2. Abra uma janela de SSH por VM (ver `integracao.md`, seção 8) e rode `sudo -v` em cada uma.
3. Gere um backup novo, no `banco`: `sudo bash ~/projeto-infraestrutura-linux/02-Luiz-Banco-de-Dados/backups/backup.sh`. No `samba`, confira com `sudo ls -l /srv/samba/dados`.

| # | Onde | Comando | O que mostrar |
|---|---|---|---|
| 1 | roteador | `ip -br a` e `sudo nft list ruleset \| head -45` | as 3 zonas e o firewall com `policy drop` |
| 2 | samba (LAN) | `sudo bash testes/conectividade/teste-conectividade.sh samba` | o que a LAN alcança e o que é bloqueado |
| 3 | samba (LAN) | `timeout 3 bash -c 'echo > /dev/tcp/192.168.30.10/5432' && echo ABERTA \|\| echo BLOQUEADA` | **BLOQUEADA**: o banco é invisível para a LAN |
| 4 | web | o mesmo comando do item 3 | **ABERTA**: só o Web alcança o banco |
| 5 | samba (LAN) | `bash testes/servicos/teste-servicos.sh cliente` | CRUD completo pelo usuário (POST 201, GET 200, PUT 200, DELETE 204) |
| 6 | web | `sudo bash testes/servicos/teste-servicos.sh web` | `DATABASE_URL` aponta ao PostgreSQL e há conexão TCP com `192.168.30.10:5432` |
| 7 | web | `curl -m 5 -sI https://example.com >/dev/null && echo COM INTERNET \|\| echo SEM INTERNET` | **SEM INTERNET**: Web isolado |
| 8 | banco, depois web | `sudo systemctl stop postgresql`; no web `curl -i localhost/health/ready \| head -1`; no banco `sudo systemctl start postgresql`; no web o `curl` de novo | **503** com o banco parado e **200** quando volta, sem reiniciar a API |
| 9 | samba | `smbclient //localhost/dados -U usr_dados%<senha> -c ls` e depois `-U usr_web%<senha>` | o primeiro lista; o segundo dá `NT_STATUS_ACCESS_DENIED` |
| 10 | cada VM | `grep -hE '^\[(FAIL\|AVISO)\]\|^PASS=' resultados/*.log` | resumo: nenhum `[FAIL]` |

As senhas dos usuários do Samba foram combinadas no grupo e **não** ficam neste repositório.

## Requisitos nas VMs

`bash`, `curl`, `ping` e `ss` (já vêm no Ubuntu Server). Papel `samba`: `testparm` e `pdbedit` (pacote `samba`). Papel `banco`: `psql` e, para verificar a cópia no Samba, `smbclient`.

## Antes de enviar ao GitHub

- Copie `.gitattributes` para a **raiz** do repositório (`*.sh text eol=lf`): sem isso, o Windows grava finais de linha que quebram os scripts no Linux.
- Os logs finais das 4 VMs ficam em `resultados/logs-finais/<vm>/`.
