#!/bin/bash
# Autor: Stageddat
# Description: Install Odoo 19 for SGE automatically

set -euo pipefail
IFS=$'\n\t'

ODOO_DIR="/opt/odoo/odoo"
ODOO_CONF="/etc/odoo.conf"
ODOO_SERVICE="/etc/systemd/system/odoo.service"
DB_NAME="ODOO_BD"
DB_USER="odoo"
LINUX_USER="isard"

echo "==============================================================="
echo " Instalador automático de terrenaitor 3000 v0.4"
echo " Descargar e instalar Odoo 19 SGE automáticamente"
echo "==============================================================="
sleep 3

#  Comprobar si ya está instalado 
if [ -d "$ODOO_DIR" ] || [ -f "$ODOO_CONF" ]; then
    echo "Se ha detectado una instalación anterior."
    read -p "¿Quieres eliminar la instalación anterior? [s/N]: " confirm
    confirm=${confirm:-N}
    if [[ "$confirm" =~ ^[sS]$ ]]; then
        echo "Eliminando instalación anterior..."
        sudo systemctl stop odoo 2>/dev/null || true
        sudo systemctl disable odoo 2>/dev/null || true
        [ -d "$ODOO_DIR" ] && sudo rm -rf "$ODOO_DIR"
        [ -f "$ODOO_CONF" ] && sudo rm -f "$ODOO_CONF"
        [ -d "/var/log/odoo" ] && sudo rm -rf /var/log/odoo
        if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
            sudo -u postgres psql -c "DROP DATABASE $DB_NAME;"
        fi
        if sudo -u postgres psql -c "\du" | cut -d \| -f 1 | grep -qw "$DB_USER"; then
            sudo -u postgres psql -c "DROP ROLE $DB_USER;"
        fi
        echo "Instalación anterior eliminada."
    else
        echo "Instalación cancelada."
        exit 0
    fi
fi


# 1. Actualizar el sistema
echo "1.  Actualizando el sistema..."
sudo apt update -y && sudo apt upgrade -y

# 2. Instalar PostgreSQL
echo "2.  Instalando PostgreSQL..."
sudo apt install -y postgresql postgresql-contrib

# 3. Configurar de PostgreSQL
echo "3. Configurando PostgreSQL..."

# Generar contraseña admin
ADMIN_PASS=$(openssl rand -hex 12)

read -p "Introduce la contraseña de PG para el usuario 'odoo' (deja vacío para usar la de admin): " -s DB_PASS
echo
if [ -z "$DB_PASS" ]; then
  echo "No se ha introducido ninguna contraseña."
  DB_PASS="$ADMIN_PASS"
fi
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}' SUPERUSER;"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"

# 4. Instalar Python i deps
echo "4. Instalando Python y dependencias..."
sudo apt install -y python3 python3-pip python3-dev python3-setuptools libpq-dev \
git build-essential wget libldap2-dev libsasl2-dev python3-wheel \
libxml2-dev libxslt1-dev libjpeg-dev zlib1g-dev libffi-dev libssl-dev \
libmysqlclient-dev libblas-dev libatlas-base-dev wkhtmltopdf || \
sudo apt install -y libmariadb-dev-compat

# 5. Instalar manualmente wkhtmltopdf
if ! command -v wkhtmltopdf &> /dev/null; then
  echo "No se ha encontrado wkhtmltopdf. Instalando manualmente..."
  wget -q https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.4/wkhtmltox-0.12.4_linux-generic-amd64.tar.xz
  tar -xJf wkhtmltox-0.12.4_linux-generic-amd64.tar.xz
  sudo mkdir -p /usr/local/bin
  sudo cp ./wkhtmltox/bin/wkhtmltopdf ./wkhtmltox/bin/wkhtmltoimage /usr/local/bin/
  sudo chmod +x /usr/local/bin/wkhtmltopdf /usr/local/bin/wkhtmltoimage
  echo "wkhtmltopdf instalado correctamente."
fi

# 6. Descargar Odoo
echo "6. Descargar Odoo 19..."
sudo git clone --depth 1 --branch 19.0 https://github.com/odoo/odoo.git "$ODOO_DIR"

# Fix: crear y configurar logs de odoo
sudo mkdir -p /var/log/odoo
sudo chown -R "$LINUX_USER":"$LINUX_USER" /var/log/odoo
sudo chmod -R 755 /opt/odoo

# 7. Crear venv
echo "7. Creando entorno virtual Python..."
sudo apt install -y python3-venv
cd "$ODOO_DIR"
python3 -m venv venv
source venv/bin/activate

# 8. Instalar deps Python
echo "8. Instalar deps de Python..."
pip install --upgrade pip wheel
if ! pip install -r requirements.txt; then
  echo "Error durant la instal·lació de dependències. Reintentant..."
  pip install --break-system-packages -r requirements.txt || {
    echo "No s'han pogut instal·lar totes les dependències."
    exit 1
  }
fi

# 9. Configurar odoo.conf
echo "9. Configurando archivo /etc/odoo.conf..."
sudo mkdir -p /var/log/odoo
# Fix: Configurar permisos de la carpeta
sudo chown -R "$LINUX_USER":"$LINUX_USER" /opt/odoo
sudo chmod -R 755 /var/log/odoo

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

# 10. Crear systemd
# echo "10. Creando sistema systemd para Odoo..."
# sudo tee "$ODOO_SERVICE" > /dev/null <<EOL
# [Unit]
# Description=Servei Odoo 19
# After=network.target postgresql.service

# [Service]
# User=$USER
# Group=$USER
# ExecStart=/opt/odoo/odoo/venv/bin/python3 /opt/odoo/odoo/odoo-bin -c /etc/odoo.conf
# Restart=always

# [Install]
# WantedBy=multi-user.target
# EOL

# sudo systemctl daemon-reload
# sudo systemctl enable odoo
# sudo systemctl start odoo

# 11. Configurar UFW
# echo "11. Configurando UFW..."
# sudo ufw allow 8069
# sudo ufw allow 80/tcp
# sudo ufw allow ssh
# sudo ufw --force enable

# 12. Verificar
echo "12. Verificando si tengo hambre..."
IP=$(hostname -I | awk '{print $1}')
echo "==============================================================="
echo " Instalado correctament."
echo " Archivo de configuración: $ODOO_CONF"
echo " Contraseña de la base de datos: ${DB_PASS}"
echo " Contrasena de administrador: ${ADMIN_PASS}"
echo " Acceder a Odoo:"
echo "     http://${IP}:8069"
echo "==============================================================="
