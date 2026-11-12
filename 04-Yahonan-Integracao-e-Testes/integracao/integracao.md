# Integração e Arquitetura (InfraLab)

**Objetivo:** mapear a topologia, a responsabilidade de cada integrante, o endereçamento e a matriz de acessos imposta pelo firewall, e registrar como os componentes se ligam entre si.

## 1. Visão geral

Um roteador com firewall separa três redes. Cada zona só fala com quem precisa.

```
                      Internet (NAT do VMware)
                               |
                          [WAN  ens32]
                   +-----------------------+
                   |  router-fw   (Ysaac)  |  nftables · NAT · DNS/DHCP (dnsmasq)
                   +--+--------+--------+--+
            [ens33]   |  [ens34]|        | [ens35]
          192.168.10.1|192.168.20.1      | 192.168.30.1
                      |         |        |
         DMZ 192.168.10.0/24  LAN 192.168.20.0/24  DB 192.168.30.0/24
         +--------------+  +-----------------+  +----------------+
         | web   .10    |  | samba  .10      |  | banco   .10    |
         | Nginx + API  |  | clientes (DHCP  |  | PostgreSQL     |
         | (Paulo)      |  | .100–.200)      |  | (Luiz)         |
         +--------------+  | (Rafael)        |  +----------------+
                           +-----------------+
```

## 2. Zonas, serviços e responsáveis

| Zona (interface no laboratório) | Hostname | IP | Serviço | Porta | Responsável |
|---|---|---|---|---|---|
| **WAN** (`ens32`) | `router-fw` | DHCP do VMware NAT (ex.: `192.168.165.129`) | Gateway, NAT, nftables | — | Ysaac |
| **DMZ** (`ens33`) | `web` | `192.168.10.10` (gateway `.10.1`) | Nginx → API FastAPI (`127.0.0.1:8000`) | 80 | Paulo |
| **LAN** (`ens34`) | `samba` e clientes | `192.168.20.10` (gateway `.20.1`) | Samba (compartilhamentos) | 139, 445 | Rafael |
| **DB Zone** (`ens35`) | `banco` | `192.168.30.10` (gateway `.30.1`) | PostgreSQL | 5432 | Luiz |

DNS e DHCP rodam no roteador (dnsmasq): nomes `web`, `db`, `files` e `router` em `.projeto.local`; faixa DHCP `192.168.20.100–200`.

**Nomes das interfaces:** no repositório do Ysaac são `ens33/37/38/39` (WAN/DMZ/LAN/DB). Nas VMs deste laboratório o Ubuntu nomeou `ens32/33/34/35`, na mesma ordem. As interfaces foram associadas pelo endereço MAC de cada placa do VMware, e os arquivos `netplan.yaml` e `nftables.conf` foram ajustados só na cópia usada no roteador.

## 3. Matriz de acesso (firewall / nftables)

Fonte da verdade dos testes de conectividade e segurança. Política padrão `drop` em `input` e `forward`.

| Origem | Destino | Porta | Ação | Observação |
|---|---|---|---|---|
| LAN | Web (DMZ) | 80, 443 e ping | **PERMITIR** | O site é acessado a partir da LAN |
| LAN | Internet | 80, 443 | **PERMITIR** | O repositório restringe a 80/443 (ver nota abaixo) |
| LAN | Roteador | SSH 22, DNS 53, DHCP 67 | **PERMITIR** | Administração e serviços de rede |
| LAN | Banco | qualquer | **BLOQUEAR** | Impede ataque direto ao banco |
| Web (DMZ) | Banco (DB) | **só 5432** | **PERMITIR** | Única dependência da API |
| Web (DMZ) | LAN / Samba | qualquer | **BLOQUEAR** | A aplicação não alcança a rede interna |
| Web (DMZ) | Internet | qualquer | **BLOQUEAR** | Estado final (sem a regra temporária) |
| Banco (DB) | Samba (LAN) | **139, 445** só para `192.168.20.10` | **PERMITIR** | Envio de backups |
| Banco (DB) | Web, LAN, Internet | qualquer | **BLOQUEAR** | Isolamento total |
| Internet (WAN) | Web, Banco, Samba | qualquer | **BLOQUEAR** | Não há regra de encaminhamento da WAN para dentro |
| Internet (WAN) | Roteador | SSH 22 | **AVISO (aceito)** | Exceção de administração remota |

> **Nota (LAN → Internet):** no repositório, o `nftables.conf` do Ysaac já restringe a saída da LAN às portas 80 e 443. O roteador do laboratório foi configurado antes desse commit e ainda usa a regra anterior (qualquer porta), por isso o teste de segurança do roteador mostra esse `[AVISO]`. Foi aceito para a entrega e está registrado em `validacao.md`.

## 4. Fluxos de comunicação validados

| Fluxo | Caminho | Prova |
|---|---|---|
| A. Usuário abre o site | Cliente (LAN) → firewall → Nginx :80 → API :8000 | `teste-servicos.sh cliente` |
| B. Site grava no banco | API → firewall → PostgreSQL :5432 | `teste-servicos.sh web` (conexão TCP) e `banco` (conexão vinda do Web) |
| C. Backup do banco | Banco → firewall → Samba :445 (share `dados`) | `teste-servicos.sh banco` (dump presente no Samba) |
| D. Nomes e IP | Cliente → dnsmasq no roteador | `teste-conectividade.sh` (DNS) |
| E. Arquivos | Cliente → Samba (mesma rede) | `smbclient` por grupo |

## 5. Configurações que ligam os componentes

| Componente | Configuração aplicada |
|---|---|
| **Banco** | `listen_addresses = 'localhost,192.168.30.10'`; no `pg_hba.conf`: `host infralab_db infralab_user 192.168.10.10/32 scram-sha-256` |
| **Web** | `DATABASE_URL=postgresql+psycopg2://infralab_user:<senha>@192.168.30.10:5432/infralab_db` carregado por `EnvironmentFile` na unit; `DEBUG=False`; API só em `127.0.0.1:8000` |
| **Backup do banco** | `backup.sh` envia o `.dump` ao share `dados` do Samba com o usuário `usr_dados`; credenciais em `/etc/infralab/samba-credentials` (root:postgres, modo 640, **não versionado**) |
| **Samba** | usuários `usr_web`, `usr_dados`, `usr_admin` com senha Samba (`smbpasswd -a`); `hosts allow = 192.168.20.0/24 192.168.30.10 127.0.0.1` |
| **Roteador** | `ip_forward=1`, nftables e dnsmasq habilitados no boot |

Senhas não são versionadas em nenhum arquivo deste repositório.

## 6. Ordem de montagem no VMware Workstation

1. **Redes virtuais** (*Edit → Virtual Network Editor*): VMnet2 (DMZ), VMnet3 (LAN) e VMnet4 (DB) como *Host-only*, com **DHCP do VMware desligado** e sem adaptador virtual do host. A WAN usa a VMnet8 (NAT).
2. **router-fw** (4 placas na ordem NAT, VMnet2, VMnet3, VMnet4): netplan, `ip_forward`, dnsmasq e nftables.
3. **banco** (VMnet4): PostgreSQL e `configurar-banco.sh`; depois `listen_addresses` e `pg_hba.conf`.
4. **web** (VMnet2): API e Nginx.
5. **samba** (VMnet3): Samba, grupos, usuários e senhas.
6. Durante as instalações, o roteador mantém uma **regra temporária** de saída para a internet (80/443) das zonas DMZ e DB, usada para `apt` e `pip`. Ao final, ela é **removida** e os testes rodam em `MODO=final`.

Instalador: cada VM precisa de 2 GB de RAM durante a instalação; depois pode voltar a 1 GB.

## 7. Configuração de rede dos servidores

O repositório não traz o `netplan` das VMs de servidor; este é o modelo usado (troque IP e gateway conforme a seção 2; confira a placa com `ip a`):

```yaml
# /etc/netplan/50-cloud-init.yaml  (exemplo: web)
network:
  version: 2
  ethernets:
    ens32:
      dhcp4: false
      addresses: [192.168.10.10/24]
      routes:
        - to: default
          via: 192.168.10.1
      nameservers:
        addresses: [192.168.10.1]
        search: [projeto.local]
```

Aplicar: `sudo chmod 600 /etc/netplan/*.yaml && sudo netplan apply`.

## 8. Acesso às VMs pelo PowerShell (SSH)

O roteador é o único alcançável direto pelo Windows; as demais passam por ele (`-J`):

```powershell
ssh teste@192.168.165.129                                  # roteador
ssh -J teste@192.168.165.129 web@192.168.10.10             # web
ssh -J teste@192.168.165.129 testebanco@192.168.30.10      # banco
ssh -J teste@192.168.165.129 samba@192.168.20.10           # samba
```

## 9. Como testar

Ver `README.md` (seção "Como rodar") para os comandos e o roteiro de demonstração, e `validacao/validacao.md` para os resultados.
