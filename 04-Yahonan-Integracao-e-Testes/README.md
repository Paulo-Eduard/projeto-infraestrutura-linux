# 04 — Integração e Testes (Yahonan)

**Objetivo:** garantir o funcionamento integrado da infraestrutura InfraLab (DMZ, LAN e DB Zone).

## O que tem aqui

| Pasta / arquivo | Para quê |
|---|---|
| [`integracao/integracao.md`](integracao/integracao.md) | Mapa da arquitetura, quem faz o quê, fluxos, ordem de montagem no VMware, netplan dos servidores e pendências por responsável |
| [`testes/conectividade/teste-conectividade.sh`](testes/conectividade/teste-conectividade.sh) | Gateway, DNS e matriz de acesso do firewall (o que deve passar e o que deve ser bloqueado) |
| [`testes/servicos/teste-servicos.sh`](testes/servicos/teste-servicos.sh) | Serviços, portas, ligação Web ↔ Banco, backups e CRUD completo pela LAN |
| [`testes/seguranca/teste-seguranca.sh`](testes/seguranca/teste-seguranca.sh) | Exposição de portas e configurações seguras de cada componente |
| [`validacao/validacao.md`](validacao/validacao.md) | Requisitos × testes, achados, procedimentos manuais, registro de execução e critérios de aprovação |
| `resultados/` | Logs gerados pelos scripts (evidências) |

## Como rodar

Copie o repositório para cada VM e execute **no console da VM** (o firewall não permite SSH da LAN para o Web e o Banco):

```bash
cd 04-Yahonan-Integracao-e-Testes
sudo bash testes/conectividade/teste-conectividade.sh [papel]
sudo bash testes/servicos/teste-servicos.sh [papel]
sudo bash testes/seguranca/teste-seguranca.sh [papel]
```

- **Papéis:** `roteador`, `banco`, `web`, `samba`, `cliente`. Sem argumento, o papel é detectado pelo IP da VM.
- **Modos:** `MODO=final` (padrão, estado de entrega) ou `MODO=dev` (durante a instalação, com a regra temporária de internet ainda ativa).
- **Saída:** `[PASS]`, `[FAIL]`, `[AVISO]` (decisão pendente) e `[INFO]`; log em `resultados/`; código de saída diferente de zero se houver `[FAIL]`.
- **Endereços diferentes?** Sobrescreva por variável de ambiente, por exemplo `WEB=192.168.10.20 sudo -E bash ...`.

## Ordem recomendada

1. `roteador` (confirma que todos os hosts respondem; evita falso "bloqueado").
2. `banco` → `web` → `samba`.
3. `cliente` (visão do usuário: site, CRUD, exposição de portas).
4. Preencher `validacao/validacao.md` com os resultados.

## Requisitos nas VMs

`bash`, `curl`, `ping` e `ss` (já vêm no Ubuntu Server). Papel `cliente`: `curl`. Papel `samba`: `testparm` e `pdbedit` (pacote `samba`). Papel `banco`: `psql` (pacote `postgresql`).

## Antes de enviar ao GitHub

Copie `.gitattributes` para a **raiz** do repositório (`*.sh text eol=lf`) para evitar o problema de final de linha do Windows que quebra scripts no Linux.
