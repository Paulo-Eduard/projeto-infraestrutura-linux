#Criacao dos grupos e usuarios do servidor
set -e
for g in gpr_todos gpr_web gpr_dados gpr_admin; do getent group "$g" > /dev/null || groupadd "$g"
done
criar_usuario() {
  id "$1" > /dev/null 2>&1 || useradd -M -s /usr/sbin/nologin -G "$2" "$1" 
}
criar_usuario usr_web gpr_todos,gpr_web
criar_usuario usr_dados gpr_todos,gpr_dados
criar_usuario usr_admin gpr_todos,gpr_web,gpr_dados,gpr_admin

# Senha do Samba (separada da senha do Linux).
# O smbpasswd pede a senha na hora; nenhuma senha fica gravada neste arquivo.
for u in usr_web usr_dados usr_admin; do
  if pdbedit -L | grep -q "^$u:"; then
    echo "$u ja esta cadastrado no Samba."
  else
    echo "Defina a senha do Samba para $u"
    smbpasswd -a "$u"
  fi
done
