# Validação e Resultados (InfraLab)

**Objetivo:** Registrar o cruzamento entre os requisitos do projeto e as evidências geradas pelos testes automatizados de integração, conectividade e segurança.

## 1. Registro de Execução (Cenário Final)

- **Ambiente:** VMware (InfraLab) - Estado de Produção (`MODO=final`)
- **Regras Temporárias:** Regra de forward de internet para atualizações de DMZ/DB **removida**.
- **Resultado Geral:** Sistema integrado, funcional e restrito conforme a matriz de acessos.

| Máquina (Papel) | Falhas (`[FAIL]`) | Avisos (`[AVISO]`) | Status de Aprovação | Observações |
|---|:---:|:---:|---|---|
| **Roteador** | 0 | 2 | **APROVADO** | Avisos documentados: Tráfego da LAN liberado em todas as portas; SSH exposto na WAN. Aceitos pela equipe. |
| **Web** | 0 | 0 | **APROVADO** | Nginx funcional, proxy configurado, sem internet (isolamento ativo). |
| **Banco** | 0 | 0 | **APROVADO** | PostgreSQL respondendo apenas à DMZ. Rede totalmente isolada. |
| **Samba / Cliente** | 0 | 0 | **APROVADO** | Acesso aos compartilhamentos validado; CRUD na API respondendo com dados reais. |

## 2. Requisitos vs. Evidências

| Requisito do Projeto | Script Validador | Resultado Esperado | Evidência (Log `resultados/`) |
|---|---|---|---|
| **Segmentação em 3 Zonas (DMZ, LAN, DB)** | `teste-conectividade.sh` | Pings e rotas entre zonas não autorizadas devem falhar (timeout). | `[PASS] Ping para DB bloqueado` |
| **Integração Aplicação ↔ Banco** | `teste-servicos.sh` | `curl` na API do Web deve retornar dados reais buscando do PostgreSQL. | `[PASS] API retornando dados (HTTP 200)` |
| **Isolamento de Internet (Segurança)** | `teste-seguranca.sh` | Acesso à WAN (8.8.8.8) por parte do Web e Banco deve ser rejeitado. | `[PASS] Internet bloqueada na DMZ/DB` |
| **Disponibilidade de Arquivos (Samba)** | `teste-servicos.sh` | `smbclient -L` deve listar as *shares* e permissões corretamente da LAN. | `[PASS] Servidor Samba lista shares` |
| **Hardening de Serviços** | `teste-seguranca.sh` | Ausência de versão nos headers do Nginx (`server_tokens off`). | `[PASS] Ocultação de headers (Nginx)` |

## 3. Critérios de Conclusão e Entrega

A bateria final atesta que:
1. **Não existem `[FAIL]` nos logs da versão de entrega.**
2. A aplicação FastAPI consome o banco de dados sem que o banco esteja exposto à rede de clientes (LAN).
3. Caso a VM Web seja comprometida, o invasor não consegue baixar scripts maliciosos da internet nem pivotar o ataque para a rede corporativa (LAN).
4. **Evidências salvas:** Todos os logs originais das 4 VMs estão centralizados na pasta `resultados/` deste repositório para auditoria.
