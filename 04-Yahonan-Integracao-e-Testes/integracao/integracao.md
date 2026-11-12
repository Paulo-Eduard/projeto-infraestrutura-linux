# Integração e Arquitetura (InfraLab)

**Objetivo:** Mapear a topologia da rede, a responsabilidade de cada integrante, o endereçamento (netplan) e a matriz de acessos imposta pelo firewall.

## 1. Zonas, Serviços e Responsáveis

| Zona (Interface) | Hostname | IP | Serviço | Porta | Responsável |
|---|---|---|---|---|---|
| **WAN** (`ens32`) | `router-fw` | `192.168.165.129` | Gateway, NAT e nftables | N/A | Ysaac |
| **DMZ** (`ens33`) | `web` | `192.168.10.10` | Nginx + FastAPI | 80, 443 | Paulo |
| **LAN** (`ens34`) | `samba` / `cliente` | `192.168.20.10` | Compartilhamento de Arquivos | 445 | Rafael |
| **DB Zone** (`ens35`) | `banco` | `192.168.30.10` | PostgreSQL | 5432 | Luiz |

## 2. Matriz de Acesso (Firewall / nftables)

Esta é a "fonte da verdade" para os scripts de testes de segurança e conectividade. O estado de produção exige bloqueios severos (Privilégio Mínimo).

| Origem | Destino | Serviço / Porta | Ação Esperada | Justificativa / Observação |
|---|---|---|---|---|
| WAN (Internet) | DMZ (`web`) | HTTP/HTTPS (80, 443) | **PERMITIR** | Acesso público à aplicação. |
| WAN (Internet) | Roteador | SSH (22) | **AVISO** (Aceito) | Exceção aprovada para administração remota. |
| WAN (Internet) | Banco / Samba | Qualquer | **BLOQUEAR** | Isolamento total do ambiente interno. |
| DMZ (`web`) | DB Zone (`banco`) | PostgreSQL (5432) | **PERMITIR** | Necessário para a API (FastAPI) consultar o banco. |
| DMZ (`web`) | WAN (Internet) | Qualquer | **BLOQUEAR** | Impede exfiltração de dados caso a aplicação seja comprometida. |
| DMZ (`web`) | LAN (`samba`) | Qualquer | **BLOQUEAR** | A aplicação não deve acessar arquivos internos da rede corporativa. |
| LAN (`cliente`) | DMZ (`web`) | HTTP/HTTPS (80, 443) | **PERMITIR** | Usuários internos acessam o sistema web. |
| LAN (`cliente`) | WAN (Internet) | Qualquer | **PERMITIR** | Usuários internos precisam de navegação. |
| LAN (`cliente`) | DB Zone (`banco`) | Qualquer | **BLOQUEAR** | Previne ataques internos diretos ao banco de dados. |

## 3. Fluxo de Comunicação Validado

1. O **Cliente (LAN)** faz uma requisição HTTP para o IP da **DMZ (Web)**.
2. O **Nginx** na DMZ atua como proxy reverso para o **FastAPI**.
3. O **FastAPI** processa a requisição e abre uma conexão exclusivamente na porta `5432` com a **DB Zone (Banco)**.
4. O **Banco de Dados** retorna os dados via rede interna (sem rota de internet).
5. O **Cliente (LAN)** recebe a resposta HTTP montada pela Web, validando a integração ponta a ponta (CRUD).
