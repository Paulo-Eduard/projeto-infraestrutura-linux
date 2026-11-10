# Configuração de Firewall de Referência (UFW / iptables)

## Regras Recomendadas para o Servidor Web

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw allow 22/tcp     # SSH (libere ANTES de habilitar o UFW)
sudo ufw allow 80/tcp     # Nginx HTTP
sudo ufw allow 443/tcp    # Nginx HTTPS (quando habilitado)

# A porta 8000 (Uvicorn) NÃO deve ser aberta: o backend escuta apenas em 127.0.0.1.

sudo ufw enable
sudo ufw status verbose
```

## Saída para o PostgreSQL

Com a política padrão `allow outgoing`, nada a fazer. Se o egress for restrito:

```bash
sudo ufw allow out to 192.168.30.10 port 5432 proto tcp
```

No servidor de banco (192.168.30.10), o `pg_hba.conf` e o firewall devem permitir a
conexão de `infralab_user` vindo do IP deste servidor web.
