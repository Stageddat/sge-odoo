#!/bin/bash
# Autor: Stageddat

set -euo pipefail
IFS=$'\n\t'

ODOO_DIR="/opt/odoo/odoo"
ODOO_CONF="/etc/odoo.conf"
ODOO_SERVICE="/etc/systemd/system/odoo.service"
DB_NAME="odoo_bd"
DB_USER="odoo"

echo "==============================================================="
echo " Instalator automatico de tu madre"
echo "==============================================================="
sleep 3

# --- Comprovar si ya esta instalao ---
if [ -d "$ODOO_DIR" ] || [ -f "$ODOO_CONF" ]; then
  echo "Se ha encotrado una instalacion anterior."
  read -p "Quieres eliminar la instalacion anterior? [s/n]: " confirm
  confirm=${confirm:-s}
  if [[ "$confirm" =~ ^[sS]$ ]]; then
    echo "Eliminando instalacion anterior..."
    sudo systemctl stop odoo 2>/dev/null || true
    sudo systemctl disable odoo 2>/dev/null || true
    sudo rm -rf "$ODOO_DIR" "$ODOO_CONF" "$ODOO_SERVICE" /var/log/odoo
    sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 && \
      sudo -u postgres psql -c "DROP DATABASE ${DB_NAME};" || true
    sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 && \
      sudo -u postgres psql -c "DROP ROLE ${DB_USER};" || true
    echo "Instalacion anterior eliminada."
  else
    echo "Instalacion cancelada por el usuario."
    exit 0
  fi
fi


# --- 1. Actualitzar el sistema ---
echo "1. Actualizando el sistema..."
sudo apt update -y && sudo apt upgrade -y

# --- 2. Instalar PostgreSQL ---
echo "2. Instalando PostgreSQL..."
sudo apt install -y postgresql postgresql-contrib

# --- 3. Configurar de PostgreSQL ---
echo "3. Configurando PostgreSQL..."
read -p "Introduce la contraseña de PG para el usuario 'odoo': " -s DB_PASS
echo
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}' SUPERUSER;"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"

# --- 4. Instalar Python i dep ---
echo "4. Instal·lant Python i dependències..."
sudo apt install -y python3 python3-pip python3-dev python3-setuptools libpq-dev \
git build-essential wget libldap2-dev libsasl2-dev python3-wheel \
libxml2-dev libxslt1-dev libjpeg-dev zlib1g-dev libffi-dev libssl-dev \
libmysqlclient-dev libblas-dev libatlas-base-dev wkhtmltopdf || \
sudo apt install -y libmariadb-dev-compat

# --- 5. Instalar manualmente wkhtmltopdf ---
if ! command -v wkhtmltopdf &> /dev/null; then
  echo "wkhtmltopdf no trobat. Instal·lant manualment..."
  wget -q https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.4/wkhtmltox-0.12.4_linux-generic-amd64.tar.xz
  tar -xJf wkhtmltox-0.12.4_linux-generic-amd64.tar.xz
  sudo mkdir -p /usr/local/bin
  sudo cp ./wkhtmltox/bin/wkhtmltopdf ./wkhtmltox/bin/wkhtmltoimage /usr/local/bin/
  sudo chmod +x /usr/local/bin/wkhtmltopdf /usr/local/bin/wkhtmltoimage
  echo "wkhtmltopdf instal·lat correctament."
fi

# --- 6. Descargar Odoo ---
echo "6. Descargar Odoo 19..."
sudo git clone --depth 1 --branch 19.0 https://github.com/odoo/odoo.git "$ODOO_DIR"
sudo chown -R "$USER":"$USER" /opt/odoo
sudo chmod -R 755 /opt/odoo

# --- 7. Crear venv ---
echo "7. Creando entorno virtual Python..."
sudo apt install -y python3-venv
cd "$ODOO_DIR"
python3 -m venv venv
source venv/bin/activate

# --- 8. Instalar deps Python ---
echo "8. Instalar deps de Python..."
pip install --upgrade pip wheel
if ! pip install -r requirements.txt; then
  echo "Error durant la instal·lació de dependències. Reintentant..."
  pip install --break-system-packages -r requirements.txt || {
    echo "No s'han pogut instal·lar totes les dependències."
    exit 1
  }
fi

# --- 9. Configurar odoo.conf ---
echo "9. Configurando archivo /etc/odoo.conf..."
sudo mkdir -p /var/log/odoo
ADMIN_PASS=$(openssl rand -hex 12)
sudo tee "$ODOO_CONF" > /dev/null <<EOL
[options]
admin_passwd = ${ADMIN_PASS}
db_host = localhost
db_port = 5432
db_user = ${DB_USER}
db_password = ${DB_PASS}
addons_path = /opt/odoo/odoo/addons
logfile = /var/log/odoo/odoo.log
xmlrpc_interface = 0.0.0.0
EOL

sudo chmod 640 "$ODOO_CONF"

# --- 10. Crear systemd ---
echo "10. Creando sistema systemd para Odoo..."
sudo tee "$ODOO_SERVICE" > /dev/null <<EOL
[Unit]
Description=Servei Odoo 19
After=network.target postgresql.service

[Service]
User=$USER
Group=$USER
ExecStart=/opt/odoo/odoo/venv/bin/python3 /opt/odoo/odoo/odoo-bin -c /etc/odoo.conf
Restart=always

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload
sudo systemctl enable odoo
sudo systemctl start odoo

# --- 11. Configurar UFW ---
echo "11. Configurando UFW..."
sudo ufw allow 8069
sudo ufw allow 80/tcp
sudo ufw allow ssh
sudo ufw --force enable

# --- 12. Verificar ---
echo "12. Verificando si tu madre esta gorda..."
if systemctl is-active --quiet odoo; then
  IP=$(hostname -I | awk '{print $1}')
  echo "==============================================================="
  echo " Instalado correctament."
  echo " Archivo de configuracion: $ODOO_CONF"
  echo " Contraseña de la base de datos: ${DB_PASS}"
  echo " Contrasena de administrador: ${ADMIN_PASS}"
  echo " Servicio de Odoo: systemctl status odoo"
  echo " Acceder a Odoo:"
  echo "     http://${IP}:8069"
  echo "==============================================================="
else
  echo "Error: Odoo no ha podido iniciar. Consulta los logs:"
  echo "sudo journalctl -u odoo -f"
  exit 1
fi
