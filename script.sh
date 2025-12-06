#!/bin/bash

################################################################################
# Script de Despliegue Automatizado para VPS Ubuntu 22.04
# HestiaCP + Node.js + Docker + Coolify
# Autor: Automatizado desde documentación técnica
# Versión: 1.0
################################################################################

set -e  # Detener en caso de error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Sin color

# Funciones de utilidad
print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script debe ejecutarse como root"
        exit 1
    fi
}

prompt_input() {
    local prompt="$1"
    local var_name="$2"
    local default="$3"
    
    if [ -n "$default" ]; then
        read -p "$(echo -e ${BLUE}$prompt ${NC}[${GREEN}$default${NC}]: )" input
        eval $var_name="${input:-$default}"
    else
        read -p "$(echo -e ${BLUE}$prompt: ${NC})" input
        eval $var_name="$input"
    fi
}

################################################################################
# INICIO DEL SCRIPT
################################################################################

clear
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   Script de Despliegue Automatizado VPS                      ║
║   HestiaCP + Node.js + Docker + Coolify                      ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

check_root

print_warning "IMPORTANTE: Este script instalará y configurará:"
echo "  • HestiaCP con Nginx, PHP, MariaDB"
echo "  • Node.js (via nvm) y PM2"
echo "  • Docker y Docker Compose"
echo "  • Coolify con configuración completa"
echo ""
read -p "$(echo -e ${YELLOW}¿Desea continuar? [y/N]: ${NC})" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "Instalación cancelada"
    exit 1
fi

################################################################################
# CONFIGURACIÓN INICIAL
################################################################################

print_header "Configuración Inicial"

prompt_input "Hostname del servidor" HOSTNAME "vps-hestia"
prompt_input "Zona horaria" TIMEZONE "America/Costa_Rica"
prompt_input "Email del administrador" ADMIN_EMAIL
prompt_input "Dominio para panel HestiaCP" HESTIA_DOMAIN "panel.midominio.com"
prompt_input "Dominio para Coolify dashboard" COOLIFY_DOMAIN "coolify.midominio.com"
prompt_input "Dominio/subdominio para proxy Coolify" COOLIFY_PROXY_DOMAIN "proxy.midominio.com"

# Configurar hostname y zona horaria
print_info "Configurando hostname: $HOSTNAME"
hostnamectl set-hostname "$HOSTNAME"

print_info "Configurando zona horaria: $TIMEZONE"
timedatectl set-timezone "$TIMEZONE"

################################################################################
# ACTUALIZACIÓN DEL SISTEMA
################################################################################

print_header "Actualizando Sistema"

apt update && apt upgrade -y
print_success "Sistema actualizado"

################################################################################
# INSTALACIÓN DE HESTIACP
################################################################################

print_header "Instalando HestiaCP"

cd /tmp
wget https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh
chmod +x hst-install.sh

print_info "Iniciando instalación de HestiaCP..."
print_warning "Este proceso puede tardar 10-15 minutos"

bash hst-install.sh \
    --multiphp '7.4,8.0,8.1,8.2,8.3,8.4' \
    --quota yes \
    --webterminal yes \
    --hostname "$HESTIA_DOMAIN" \
    --email "$ADMIN_EMAIL" \
    -f

print_success "HestiaCP instalado correctamente"

################################################################################
# INSTALACIÓN DE NODE.JS
################################################################################

print_header "Instalando Node.js via NVM"

# Instalar NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

# Cargar NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Instalar Node.js 24
nvm install 24
print_success "Node.js $(node -v) instalado"

# Instalar PM2
npm install pm2 -g
print_success "PM2 $(pm2 -v) instalado"

################################################################################
# PLUGIN NODE.JS PARA HESTIACP
################################################################################

print_header "Instalando Plugin Node.js para HestiaCP"

cd /tmp
git clone https://github.com/JLFdzDev/hestiacp-nodejs.git
cd hestiacp-nodejs
chmod 755 install.sh
./install.sh

print_success "Plugin Node.js integrado en HestiaCP"

################################################################################
# INSTALACIÓN DE DOCKER
################################################################################

print_header "Instalando Docker"

# Agregar repositorio oficial de Docker
apt-get update
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker

print_success "Docker $(docker --version | cut -d' ' -f3) instalado"
print_success "Docker Compose $(docker compose version | cut -d' ' -f4) instalado"

################################################################################
# INSTALACIÓN DE COOLIFY
################################################################################

print_header "Instalando Coolify"

# Crear estructura de directorios
print_info "Creando estructura de directorios..."
mkdir -p /data/coolify/{source,ssh,applications,databases,backups,services,proxy,webhooks-during-maintenance}
mkdir -p /data/coolify/ssh/{keys,mux}
mkdir -p /data/coolify/proxy/dynamic

# Generar clave SSH
print_info "Generando clave SSH..."
ssh-keygen -f /data/coolify/ssh/keys/id.root@host.docker.internal -t ed25519 -N '' -C root@coolify
cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Descargar archivos de Coolify
print_info "Descargando archivos de Coolify..."
curl -fsSL https://cdn.coollabs.io/coolify/docker-compose.yml -o /data/coolify/source/docker-compose.yml
curl -fsSL https://cdn.coollabs.io/coolify/docker-compose.prod.yml -o /data/coolify/source/docker-compose.prod.yml
curl -fsSL https://cdn.coollabs.io/coolify/.env.production -o /data/coolify/source/.env
curl -fsSL https://cdn.coollabs.io/coolify/upgrade.sh -o /data/coolify/source/upgrade.sh

# Configurar permisos
chown -R 9999:root /data/coolify
chmod -R 700 /data/coolify

# Generar valores únicos en .env
print_info "Generando configuración segura..."
sed -i "s|APP_ID=.*|APP_ID=$(openssl rand -hex 16)|g" /data/coolify/source/.env
sed -i "s|APP_KEY=.*|APP_KEY=base64:$(openssl rand -base64 32)|g" /data/coolify/source/.env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$(openssl rand -base64 32)|g" /data/coolify/source/.env
sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=$(openssl rand -base64 32)|g" /data/coolify/source/.env
sed -i "s|PUSHER_APP_ID=.*|PUSHER_APP_ID=$(openssl rand -hex 32)|g" /data/coolify/source/.env
sed -i "s|PUSHER_APP_KEY=.*|PUSHER_APP_KEY=$(openssl rand -hex 32)|g" /data/coolify/source/.env
sed -i "s|PUSHER_APP_SECRET=.*|PUSHER_APP_SECRET=$(openssl rand -hex 32)|g" /data/coolify/source/.env

# Crear red Docker
print_info "Creando red Docker 'coolify'..."
docker network create --attachable coolify || true

# Iniciar Coolify
print_info "Iniciando contenedores de Coolify..."
docker compose --env-file /data/coolify/source/.env \
  -f /data/coolify/source/docker-compose.yml \
  -f /data/coolify/source/docker-compose.prod.yml \
  up -d --pull always --remove-orphans --force-recreate

print_success "Coolify instalado y ejecutándose"

################################################################################
# CONFIGURACIÓN DE PLANTILLAS NGINX PARA COOLIFY
################################################################################

print_header "Configurando Plantillas Nginx para Coolify"

# Plantilla para dashboard Coolify (HTTP)
cat > /usr/local/hestia/data/templates/web/nginx/coolify_proxy.tpl << 'EOF'
server {
    listen      %ip%:80;
    server_name %domain_idn% %alias_idn%;
    index       index.html index.htm index.php;

    access_log  /var/log/nginx/domains/%domain%.log combined;
    access_log  /var/log/nginx/domains/%domain%.bytes bytes;
    error_log   /var/log/nginx/domains/%domain%.error.log error;
    include %home%/%user%/conf/web/%domain%/nginx.forcessl.conf*;

    location ~ /\.(?!well-known\/|file) {
        deny all;
        return 404;
    }

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        sub_filter_once off;
        proxy_intercept_errors on;
        error_page 502 503 504 = @fallback;
    }

    location /app/ {
        proxy_pass http://127.0.0.1:6001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }

    location /terminal/ws {
        proxy_pass http://127.0.0.1:6002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }

    location @fallback {
        root %sdocroot%;
        try_files $uri $uri/ =404;
    }

    include %home%/%user%/conf/web/%domain%/nginx.conf_*;
}
EOF

# Plantilla para dashboard Coolify (HTTPS)
cat > /usr/local/hestia/data/templates/web/nginx/coolify_proxy.stpl << 'EOF'
server {
    listen      %ip%:443 ssl http2;
    server_name %domain_idn% %alias_idn%;
    index       index.html index.htm index.php;

    ssl_certificate     %ssl_pem%;
    ssl_certificate_key %ssl_key%;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_stapling        on;
    ssl_stapling_verify on;

    include %home%/%user%/conf/web/%domain%/nginx.hsts.conf*;

    location ~ /\.(?!well-known\/|file) {
        deny all;
        return 404;
    }

    access_log  /var/log/nginx/domains/%domain%.log combined;
    access_log  /var/log/nginx/domains/%domain%.bytes bytes;
    error_log   /var/log/nginx/domains/%domain%.error.log error;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        add_header 'Content-Security-Policy' 'upgrade-insecure-requests';
        sub_filter_once off;
        proxy_intercept_errors on;
        error_page 502 503 504 = @fallback;
    }

    location /app/ {
        proxy_pass http://127.0.0.1:6001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }

    location /terminal/ws {
        proxy_pass http://127.0.0.1:6002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }

    location @fallback {
        root %sdocroot%;
        try_files $uri $uri/ =404;
    }

    include %home%/%user%/conf/web/%domain%/nginx.ssl.conf_*;
}
EOF

# Plantilla para proxy Traefik (HTTP)
cat > /usr/local/hestia/data/templates/web/nginx/coolify-subdomain_proxy.tpl << 'EOF'
server {
    listen      %ip%:80;
    server_name %domain_idn% %alias_idn%;
    index       index.html index.htm index.php;

    access_log  /var/log/nginx/domains/%domain%.log combined;
    access_log  /var/log/nginx/domains/%domain%.bytes bytes;
    error_log   /var/log/nginx/domains/%domain%.error.log error;
    include %home%/%user%/conf/web/%domain%/nginx.forcessl.conf*;

    location ~ /\.(?!well-known\/|file) {
        deny all;
        return 404;
    }

    location / {
        proxy_pass http://localhost:8001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        sub_filter_once off;
        proxy_intercept_errors on;
        error_page 502 503 504 = @fallback;
    }

    location @fallback {
        root %sdocroot%;
        try_files $uri $uri/ =404;
    }

    include %home%/%user%/conf/web/%domain%/nginx.conf_*;
}
EOF

# Plantilla para proxy Traefik (HTTPS)
cat > /usr/local/hestia/data/templates/web/nginx/coolify-subdomain_proxy.stpl << 'EOF'
server {
    listen      %ip%:443 ssl http2;
    server_name %domain_idn% %alias_idn%;
    index       index.html index.htm index.php;

    ssl_certificate     %ssl_pem%;
    ssl_certificate_key %ssl_key%;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_stapling        on;
    ssl_stapling_verify on;

    include %home%/%user%/conf/web/%domain%/nginx.hsts.conf*;

    location ~ /\.(?!well-known\/|file) {
        deny all;
        return 404;
    }

    access_log  /var/log/nginx/domains/%domain%.log combined;
    access_log  /var/log/nginx/domains/%domain%.bytes bytes;
    error_log   /var/log/nginx/domains/%domain%.error.log error;

    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        add_header 'Content-Security-Policy' 'upgrade-insecure-requests';
        sub_filter_once off;
        proxy_intercept_errors on;
        error_page 502 503 504 = @fallback;
    }

    location @fallback {
        root %sdocroot%;
        try_files $uri $uri/ =404;
    }

    include %home%/%user%/conf/web/%domain%/nginx.ssl.conf_*;
}
EOF

print_success "Plantillas Nginx creadas"

# Agregar configuración para WebSocket upgrade en Nginx
print_info "Configurando soporte WebSocket en Nginx..."
NGINX_CONF="/usr/local/hestia/nginx/conf/nginx.conf"
if ! grep -q "connection_upgrade" "$NGINX_CONF"; then
    sed -i '/http {/a \    map $http_upgrade $connection_upgrade {\n        default upgrade;\n        '"''"'      close;\n    }' "$NGINX_CONF"
    print_success "Soporte WebSocket agregado a Nginx"
else
    print_info "Soporte WebSocket ya configurado"
fi

systemctl reload nginx

################################################################################
# CONFIGURAR BACKUP AUTOMÁTICO
################################################################################

print_header "Configurando Backup Automático de Coolify"

# Crear cron job para backup diario
CRON_JOB="0 3 * * * tar -czf /backup/coolify-\$(date +\\%F).tar.gz /data/coolify --exclude=/data/coolify/logs 2>/dev/null"
(crontab -l 2>/dev/null | grep -v "coolify-backup"; echo "$CRON_JOB") | crontab -

mkdir -p /backup
print_success "Backup automático configurado (3:00 AM diario)"

################################################################################
# RESUMEN FINAL
################################################################################

clear
print_header "INSTALACIÓN COMPLETADA"

SERVER_IP=$(hostname -I | awk '{print $1}')

cat << EOF
${GREEN}✓ Instalación completada exitosamente${NC}

${BLUE}═══════════════════════════════════════════════════════════════${NC}
${BLUE}  INFORMACIÓN DE ACCESO${NC}
${BLUE}═══════════════════════════════════════════════════════════════${NC}

${YELLOW}HestiaCP Panel:${NC}
  URL:      https://$SERVER_IP:8083
  URL Alt:  https://$HESTIA_DOMAIN:8083
  Usuario:  admin
  ${RED}⚠ Contraseña guardada en: /usr/local/hestia/data/admin.pass${NC}

${YELLOW}Coolify Dashboard:${NC}
  URL:      http://$SERVER_IP:8000
  ${RED}⚠ Configura proxy inverso con dominio: $COOLIFY_DOMAIN${NC}

${YELLOW}Versiones Instaladas:${NC}
  Sistema:  $(lsb_release -ds)
  Node.js:  $(node -v)
  PM2:      $(pm2 -v)
  Docker:   $(docker --version | cut -d' ' -f3)
  Compose:  $(docker compose version | cut -d' ' -f4)

${BLUE}═══════════════════════════════════════════════════════════════${NC}
${BLUE}  PRÓXIMOS PASOS${NC}
${BLUE}═══════════════════════════════════════════════════════════════${NC}

1. ${GREEN}Acceder a HestiaCP${NC} y cambiar contraseña de admin:
   cat /usr/local/hestia/data/admin.pass

2. ${GREEN}Configurar dominios en HestiaCP:${NC}
   • Dashboard Coolify: $COOLIFY_DOMAIN → plantilla 'coolify_proxy'
   • Proxy Traefik:     $COOLIFY_PROXY_DOMAIN → plantilla 'coolify-subdomain_proxy'
   • Agregar alias wildcard: *.$COOLIFY_PROXY_DOMAIN

3. ${GREEN}Configurar DNS${NC} (en tu proveedor):
   A    $COOLIFY_DOMAIN              → $SERVER_IP
   A    $COOLIFY_PROXY_DOMAIN        → $SERVER_IP
   A    *.$COOLIFY_PROXY_DOMAIN      → $SERVER_IP

4. ${GREEN}Activar SSL${NC} en HestiaCP para ambos dominios

5. ${GREEN}Configurar Coolify:${NC}
   • Servers → localhost → Configuration → Wildcard Domain: $COOLIFY_PROXY_DOMAIN
   • Servers → localhost → Proxy → Actualizar compose con puertos 8001-8003

${BLUE}═══════════════════════════════════════════════════════════════${NC}
${BLUE}  VERIFICACIÓN${NC}
${BLUE}═══════════════════════════════════════════════════════════════${NC}

${YELLOW}Comprobar servicios:${NC}
  systemctl status hestia nginx docker
  docker ps
  docker logs \$(docker ps -qf "name=coolify")

${YELLOW}Comprobar puertos:${NC}
  ss -tuln | grep -E "80|443|8083|8000|8001|6001|6002"

${YELLOW}Backup automático:${NC}
  crontab -l | grep coolify

${BLUE}═══════════════════════════════════════════════════════════════${NC}

${GREEN}Documentación completa disponible en:${NC}
  /root/deployment-docs.md

${YELLOW}¡Instalación completada! Guarda esta información.${NC}

EOF

# Guardar log de instalación
cat > /root/installation-summary.txt << EOF
Instalación completada: $(date)
Hostname: $HOSTNAME
Zona Horaria: $TIMEZONE
IP Servidor: $SERVER_IP
Email Admin: $ADMIN_EMAIL
Dominio HestiaCP: $HESTIA_DOMAIN
Dominio Coolify: $COOLIFY_DOMAIN
Dominio Proxy: $COOLIFY_PROXY_DOMAIN

Node.js: $(node -v)
PM2: $(pm2 -v)
Docker: $(docker --version)

Contraseña HestiaCP: $(cat /usr/local/hestia/data/admin.pass 2>/dev/null || echo "N/A")
EOF

print_success "Resumen guardado en /root/installation-summary.txt"

exit 0
