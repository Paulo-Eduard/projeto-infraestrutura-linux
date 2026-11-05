#!/bin/bash
# Define as cotas de disco dos usuários do Samba (executar com sudo)
for u in usr_web usr_dados usr_admin; do
  setquota -u "$u" 100000 120000 0 0 /
done
