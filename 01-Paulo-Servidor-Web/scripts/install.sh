#!/usr/bin/env bash
set -e

echo "[InfraLab] Instalação do Servidor Web Linux - Componente Paulo"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "[+] OS detectado:  ()"
fi

echo "[+] Atualizando pacotes e instalando dependências..."
sudo apt-get update -y
sudo apt-get install -y python3 python3-venv python3-pip nginx curl tar

VENV_PATH="/opt/infralab/venv"
if [ ! -d "" ]; then
    sudo python3 -m venv ""
fi

echo "[+] Instalando dependências Python..."
sudo "/bin/pip" install --upgrade pip
sudo "/bin/pip" install -r "./../fastapi/requirements.txt"

echo "[+] Configurando Nginx..."
sudo cp "./../nginx/site.conf" /etc/nginx/sites-available/infralab.conf
sudo ln -sf /etc/nginx/sites-available/infralab.conf /etc/nginx/sites-enabled/infralab.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t

echo "[+] Configurando Systemd..."
sudo cp "./../systemd/infralab-api.service" /etc/systemd/system/infralab-api.service
sudo systemctl daemon-reload

echo "[✓] Instalação concluída com sucesso!"
