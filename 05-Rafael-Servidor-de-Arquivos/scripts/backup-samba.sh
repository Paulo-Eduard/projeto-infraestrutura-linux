#!/bin/bash
# Backup das pastas compartilhadas do Samba (executar como root)
DESTINO=/srv/backups
DATA=$(date +%F_%H-%M)
ARQUIVO="$DESTINO/samba_$DATA.tar.gz"
LOG=/var/log/backup-samba.log

umask 027
if tar -czf "$ARQUIVO" -C /srv samba; then
  echo "$(date '+%F %T') OK   $ARQUIVO" >> "$LOG"
else
  echo "$(date '+%F %T') ERRO ao gerar $ARQUIVO" >> "$LOG"
  exit 1
fi
find "$DESTINO" -name 'samba_*.tar.gz' -mtime +7 -delete
