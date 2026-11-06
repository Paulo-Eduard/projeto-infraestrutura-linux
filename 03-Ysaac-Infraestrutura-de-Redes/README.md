# Ysaac - Infraestrutura de Redes

**Responsável:** Ysaac

## Visão geral

Esta parte do projeto cria o roteador/firewall (`router-fw`) que conecta e protege as três redes da infraestrutura: DMZ, LAN e DB Zone. Ele também fornece DHCP e DNS e dá acesso à internet por NAT.

- Sistema: Ubuntu Server 24.04 LTS
- Virtualização: VMware Workstation
- Serviços: Netplan, dnsmasq (DHCP e DNS), nftables (firewall)

## Plano de endereçamento

| Rede | Faixa | Gateway (router) | Hosts |
|---|---|---|---|
| WAN | DHCP do VMware (NAT) | automático | - |
| DMZ | 192.168.10.0/24 | 192.168.10.1 | Servidor Web: 192.168.10.10 |
| LAN | 192.168.20.0/24 | 192.168.20.1 | Servidor de Arquivos: 192.168.20.10 / Clientes DHCP: .100 a .200 |
| DB Zone | 192.168.30.0/24 | 192.168.30.1 | PostgreSQL: 192.168.30.10 |

## Interfaces do roteador

| Interface | Rede | VMware |
|---|---|---|
| ens33 | WAN | NAT |
| ens37 | DMZ | VMnet2 (Host-only) |
| ens38 | LAN | VMnet3 (Host-only) |
| ens39 | DB Zone | VMnet4 (Host-only) |

O DHCP do VMware deve ficar **desligado** nas VMnet2, VMnet3 e VMnet4.

## Nomes DNS (projeto.local)

| Nome | IP |
|---|---|
| router.projeto.local | 192.168.20.1 |
| web.projeto.local | 192.168.10.10 |
| db.projeto.local | 192.168.30.10 |
| files.projeto.local | 192.168.20.10 |

## Regras do firewall

- A LAN acessa a internet e o servidor Web somente nas portas 80 e 443.
- Somente o servidor Web (DMZ) acessa o PostgreSQL, na porta 5432.
- A LAN não acessa o banco de dados diretamente.
- A DMZ não acessa a LAN.
- O banco acessa o servidor de arquivos (Samba), portas 139 e 445, para enviar backups.
- Política padrão: tudo que não foi liberado é bloqueado.

## Arquivos desta pasta

| Arquivo | Função | Destino na VM |
|---|---|---|
| `rede/netplan.yaml` | IPs das interfaces | `/etc/netplan/50-cloud-init.yaml` |
| `rede/dns.conf` | Servidor DNS | `/etc/dnsmasq.d/dns.conf` |
| `rede/dhcp.conf` | Servidor DHCP | `/etc/dnsmasq.d/dhcp.conf` |
| `roteamento/99-forward.conf` | Ativa o roteamento IPv4 | `/etc/sysctl.d/99-forward.conf` |
| `firewall/nftables.conf` | Regras do firewall e NAT | `/etc/nftables.conf` |

## Como aplicar

Antes, confira os nomes das interfaces com `ip -br link`. Se forem diferentes de ens33, ens37, ens38 e ens39, ajuste o `netplan.yaml` e as linhas `define` do `nftables.conf`.

**1. IPs**
```
sudo cp netplan.yaml /etc/netplan/50-cloud-init.yaml
sudo chmod 600 /etc/netplan/50-cloud-init.yaml
sudo netplan try
```

**2. Roteamento**
```
sudo cp 99-forward.conf /etc/sysctl.d/99-forward.conf
sudo sysctl --system
```

**3. DHCP e DNS**
```
sudo apt update && sudo apt install -y dnsmasq
sudo cp dns.conf dhcp.conf /etc/dnsmasq.d/
sudo systemctl restart dnsmasq
sudo systemctl enable dnsmasq
```

**4. Firewall**
```
sudo cp nftables.conf /etc/nftables.conf
sudo nft -c -f /etc/nftables.conf
sudo systemctl enable --now nftables
```

## Testes

| Teste | Comando | Esperado |
|---|---|---|
| Internet no roteador | `ping -c 3 8.8.8.8` | Responde |
| DNS | `nslookup web.projeto.local 192.168.20.1` | 192.168.10.10 |
| Firewall ativo na inicialização | `sudo systemctl is-enabled nftables` | enabled |
| LAN para Web | `curl http://192.168.10.10` | Libera |
| LAN para Banco | `nc -zv 192.168.30.10 5432` | Bloqueia |
| Web para Banco | `nc -zv 192.168.30.10 5432` (na VM web) | Libera |
| DMZ para LAN | `ping 192.168.20.10` (na VM web) | Bloqueia |
| Banco para Samba | `nc -zv 192.168.20.10 445` (na VM do banco) | Libera |

## Observação

O `nftables.conf` contém uma regra temporária que libera as portas 80 e 443 da DMZ e da DB Zone para a internet, usada para instalar pacotes durante o desenvolvimento. Ela deve ser removida antes da apresentação final, para manter o banco isolado.
