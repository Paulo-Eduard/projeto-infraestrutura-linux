#Criacao dos grupos e usuarios do servidor
set -e
for g in gpr_todos gpr_web gpr_dados gpr_admin; do getent group "$g" > /dev/null || groupadd "$g"
done
criar_usuario() {
  id "$1" > /dev/null 2>&1 || useradd -M -s /usr/sbin/nologin -G "$2" "$1" 
}
criar_usuario usr_web gpr_todos,gpr_web
criar_usuario usr_dados gpr_todos,gpr_dados
criar_usuario usr_adim gpr_todos,gpr_web,gpr_dados,gpr_admin
