#!/bin/bash
# Odoo 19 Ubuntu Server
# Autor: Stageddat

set -e  # Parar script si falla

echo "Instal·lant Odoo 19 automàticament. Vols continuar? (Ctrl+C per cancel·lar)"
sleep 10

echo "1. Actualitzant servidor..."
sudo apt update && sudo apt upgrade -y

echo "2. Instal·lant PostgreSQL"
sudo apt install -y postgresql postgresql-contrib

echo "3. Configurant usuari i base de dades PostgreSQL"
sudo -u postgres psql -c "CREATE DATABASE odoo_bd;"
sudo -u postgres psql -c "CREATE USER odoo WITH PASSWORD 'odoo' SUPERUSER;"

echo "4. Instal·lant Python i dependències"
sudo apt install -y python3 python3-pip python3-dev python3-setuptools libpq-dev
sudo apt install -y git build-essential wget libldap2-dev libsasl2-dev python3-wheel \
libxml2-dev libxslt1-dev libjpeg-dev zlib1g-dev libffi-dev libssl-dev libmysqlclient-dev \
libblas-dev libatlas-base-dev wkhtmltopdf

# Si falla libmysqlclient-dev
sudo apt install -y libmariadb-dev-compat || true

echo "5. Instal·lant wkhtmltopdf manualment si cal"
if ! command -v wkhtmltopdf &> /dev/null; then
  wget https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.4/wkhtmltox-0.12.4_linux-generic-amd64.tar.xz
  tar -xJf wkhtmltox-0.12.4_linux-generic-amd64.tar.xz
  sudo mkdir -p /usr/local/bin
  sudo cp ./wkhtmltox/bin/wkhtmltopdf /usr/local/bin/
  sudo cp ./wkhtmltox/bin/wkhtmltoimage /usr/local/bin/
  sudo chmod +x /usr/local/bin/wkhtmltopdf /usr/local/bin/wkhtmltoimage
fi

echo "6. Descarregant Odoo 19"
sudo git clone --depth 1 --branch 19.0 https://github.com/odoo/odoo.git /opt/odoo/odoo
sudo chmod -R a+rwx /opt/odoo/

echo "7. Creant entorn virtual venv"
cd /opt/odoo/odoo
sudo apt install -y python3-venv
python3 -m venv venv
source venv/bin/activate

echo "8. Instal·lant dependències de Python"
pip install wheel
pip install -r requirements.txt

echo "9. Configurant fitxer odoo.conf"
sudo mkdir -p /var/log/odoo
sudo tee /opt/odoo/odoo/debian/odoo.conf > /dev/null <<EOL
[options]
admin_passwd = admin
db_host = localhost
db_port = 5432
db_user = odoo
db_password = odoo
logfile = /var/log/odoo/odoo.log
EOL

echo "10. Configurant firewall"
sudo ufw allow 8069
sudo ufw allow 80/tcp
sudo ufw allow ssh
sudo ufw enable

echo "11. Iniciant Odoo"
cd /opt/odoo/odoo
./odoo-bin -c ./debian/odoo.conf &
echo "✅ Odoo s'està executant. Obre el navegador a http://<IP>:8069"
