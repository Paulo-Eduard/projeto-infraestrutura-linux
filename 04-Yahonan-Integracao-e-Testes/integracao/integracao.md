# Integração dos componentes — InfraLab

> Responsável: Yahonan · Objetivo: garantir o funcionamento integrado da infraestrutura.
> Este documento é o "mapa": quem entrega o quê, como as partes se conectam e em que ordem montar tudo.

## 1. A ideia em poucas linhas

O InfraLab simula a rede de uma empresa pequena. Um **roteador com firewall** separa três redes:

- **DMZ** — onde fica o servidor **Web** (a parte "pública").
- **LAN** — onde ficam os **usuários** e o servidor de **arquivos (Samba)**.
- **DB Zone** — onde fica o **banco de dados**, isolado de todo mundo, exceto do Web.

Regra: *cada zona só fala com quem precisa*. Quem garante isso é o firewall do roteador; quem prova que funciona são os testes desta pasta.

```
                      Internet (NAT do VMware)
                               |
                          [ens33 WAN]
                   +-----------------------+
                   |   ROUTER-FW (Ysaac)   |   nftables, DHCP/DNS (dnsmasq), NAT
                   +--+--------+--------+--+
              [ens37]  |  [ens38]|        | [ens39]
          192.168.10.1 |192.168.20.1      | 192.168.30.1
                       |        |         |
        DMZ 192.168.10.0/24   LAN 192.168.20.0/24   DB 192.168.30.0/24
        +--------------+   +----------------------+  +----------------+
        | WEB .10      |   | SAMBA .10  CLIENTES  |  | BANCO .10      |
        | Nginx + API  |   | (DHCP .100-.200)     |  | PostgreSQL     |
        | (Paulo)      |   | (Rafael)             |  | (Luiz)         |
        +--------------+   +----------------------+  +----------------+
```

## 2. Quem faz o quê

| Pasta | Responsável | O que entrega | Quem depende dele |
|---|---|---|---|
| `01-Paulo-Servidor-Web` | Paulo | Nginx (porta 80) → API FastAPI (127.0.0.1:8000), unit systemd `infralab-api` | usuários da LAN |
| `02-Luiz-Banco-de-Dados` | Luiz | PostgreSQL com `infralab_db`/`infralab_user`, tabela `items`, backup diário | API do Paulo |
| `03-Ysaac-Infraestrutura-de-Redes` | Ysaac | Roteador: IPs, rotas, NAT, firewall (nftables), DNS e DHCP | todos |
| `05-Rafael-Servidor-de-Arquivos` | Rafael | Samba com 4 compartilhamentos, grupos, cotas, backup | clientes; destino de backup do banco |
| `04-Yahonan-Integracao-e-Testes` | Yahonan | este mapa, testes e validação | — |

## 3. Endereçamento

| Máquina | Zona | IP | Gateway | DNS | Nome |
|---|---|---|---|---|---|
| router-fw | todas | .1 de cada rede (WAN por DHCP do VMware) | — | — | `router.projeto.local` |
| web | DMZ | 192.168.10.10 | 192.168.10.1 | 192.168.10.1 | `web.projeto.local` |
| samba | LAN | 192.168.20.10 | 192.168.20.1 | 192.168.20.1 | `files.projeto.local` |
| clientes | LAN | DHCP 192.168.20.100–200 | 192.168.20.1 | 192.168.20.1 | — |
| banco | DB Zone | 192.168.30.10 | 192.168.30.1 | 192.168.30.1 | `db.projeto.local` |

Portas dos serviços: Web 80 (443 ainda não implementada) · API 8000 (só `127.0.0.1`) · PostgreSQL 5432 · Samba 139 e 445 · SSH 22.

## 4. Os fluxos que precisam funcionar

| Fluxo | Caminho | Exige |
|---|---|---|
| A. Usuário abre o site | Cliente → firewall → Nginx :80 → API :8000 | regra LAN→Web 80/443 (Ysaac), Nginx proxy (Paulo) |
| B. Site grava no banco | API → firewall → PostgreSQL :5432 | `listen_addresses` e `pg_hba.conf` do banco (Luiz), regra Web→DB 5432 (Ysaac), `DATABASE_URL` com IP `192.168.30.10` (Paulo) |
| C. Backup do banco para o Samba | Banco → firewall → Samba :445 | regra DB→Samba 139/445 (Ysaac), cópia no `backup.sh` (Luiz), share e usuário (Rafael) |
| D. Cliente recebe IP e nomes | Cliente → dnsmasq no roteador | DHCP/DNS (Ysaac) |
| E. Acesso aos arquivos | Cliente → Samba (mesma rede) | usuários e senhas Samba (Rafael) |

## 5. Matriz de acesso esperada (o que os testes verificam)

| Origem ↓ / Destino → | Web (DMZ) | Banco (DB) | Samba (LAN) | Internet | Roteador |
|---|---|---|---|---|---|
| **LAN** | 80, 443 e ping | ✗ | (mesma rede) | ✓ | SSH, DNS, DHCP |
| **Web** | — | **só 5432** | ✗ | ✗ (estado final) | DNS, ping |
| **Banco** | ✗ | — | **só 139/445** | ✗ (estado final) | DNS, ping |
| **Internet** | ✗ | ✗ | ✗ | — | SSH (a decidir) |

✗ = descartado pelo firewall (sem resposta). "Estado final" = depois de remover a regra temporária de internet.

## 6. Ordem de montagem no VMware Workstation

Máquinas: 5 VMs Ubuntu Server (router-fw, web, banco, samba, cliente). O roteador tem **4 placas de rede**; as demais, uma.

1. **Redes virtuais** (Virtual Network Editor): crie 3 redes *Host-only* (ex.: VMnet2 = DMZ, VMnet3 = LAN, VMnet4 = DB) com o **DHCP do VMware desligado** — quem dá IP na LAN é o dnsmasq do roteador. Desmarque "Connect a host virtual adapter" nessas redes: por padrão o adaptador do host usa o final `.1`, que é o do roteador. A WAN usa a rede NAT padrão (VMnet8).
2. **router-fw**: ens33 → NAT, ens37 → DMZ, ens38 → LAN, ens39 → DB. Aplicar netplan, nftables, dnsmasq e `ip_forward` (pasta do Ysaac). *Deixar a regra temporária de internet ativa por enquanto.*
3. **banco**: IP fixo (item 7) → instalar PostgreSQL e rodar `configurar-banco.sh` (Luiz).
4. **web**: IP fixo → instalar e subir API + Nginx (Paulo), apontando `DATABASE_URL` para `192.168.30.10`.
5. **samba**: IP fixo → instalar Samba, criar usuários e senhas (Rafael).
6. **cliente**: placa na LAN, IP por DHCP.
7. **Remover a regra temporária** do roteador (no `nftables.conf` **e** no `setup-router.sh`) e recarregar.
8. Rodar os testes (seção 8) em modo `final`.

## 7. Configuração de rede das VMs de servidor (faltava no repositório)

Nenhuma pasta entrega o `netplan` das VMs de servidor. Modelo (troque IP e gateway conforme a tabela da seção 3; confira o nome da placa com `ip a`):

```yaml
# /etc/netplan/50-cloud-init.yaml  (web; para banco e samba, mude addresses, via e nameservers)
network:
  version: 2
  ethernets:
    ens33:
      dhcp4: false
      addresses: [192.168.10.10/24]
      routes:
        - to: default
          via: 192.168.10.1
      nameservers:
        addresses: [192.168.10.1]
        search: [projeto.local]
```

Aplicar: `sudo chmod 600 /etc/netplan/*.yaml && sudo netplan apply`. Depois: `ip a`, `ip route`, `ping 192.168.10.1`, `getent hosts db.projeto.local`.

## 8. Como testar

Do console de cada VM (o firewall não deixa a LAN entrar por SSH no Web nem no Banco):

```bash
# na VM, dentro da pasta 04-Yahonan-Integracao-e-Testes
sudo bash testes/conectividade/teste-conectividade.sh   # o papel é detectado pelo IP
sudo bash testes/servicos/teste-servicos.sh
sudo bash testes/seguranca/teste-seguranca.sh
# durante a instalação (com a regra temporária de internet ainda ativa):
sudo MODO=dev bash testes/conectividade/teste-conectividade.sh
```

Ordem sugerida: `roteador` primeiro (confirma que todos os hosts respondem) → `banco` → `web` → `samba` → `cliente`. Os logs ficam em `resultados/`.

> Um resultado "filtrada" nos testes de bloqueio também aparece quando o **destino está desligado**. Por isso o teste `roteador` vem primeiro.

## 9. Pendências conhecidas por responsável

Detalhes, evidências e como cada teste detecta o problema estão em [`../validacao/validacao.md`](../validacao/validacao.md).

| Responsável | O que precisa ser feito |
|---|---|
| **Paulo** | carregar o `.env` (`EnvironmentFile` no `.service`); usar `postgresql+psycopg2://` e o IP `192.168.30.10`; não cair em SQLite; API não pode morrer se o banco estiver fora (`create_all` no import); consertar `install.sh`, `healthcheck.sh`, `backup-config.sh`, `portas.md`, `variaveis-ambiente.md` (variáveis vazias); `DEBUG=False`; esconder `/docs` |
| **Luiz** | `listen_addresses` com `192.168.30.10`; linha no `pg_hba.conf` para `192.168.10.10/32`; `pg_restore --role=infralab_user`; copiar o backup para o Samba; documentar senha com caracteres especiais (URL-encode) |
| **Ysaac** | remover a regra temporária (também do `setup-router.sh`); decidir LAN→internet "só 80/443" (README) vs "qualquer porta" (regra); decidir SSH na WAN; preencher/remover arquivos vazios |
| **Rafael** | `smbpasswd -a` para cada usuário; corrigir `usr_adim` × `usr_admin`; remover linha duplicada do crontab e instalar o `backup-samba.sh`; decidir share `web` (DMZ não alcança a LAN); `hosts allow`; preencher `configurar-samba.sh` |
| **Grupo** | quem faz o netplan dos servidores (modelo na seção 7); `.gitattributes` com `*.sh text eol=lf` na raiz; HTTPS fica fora do escopo ou entra? |
