# Documentación para despliegue: VPS Ubuntu 22.04 con HestiaCP + Node.js + Coolify

## Requisitos previos

| Recurso            | Detalle                                                 |
| ------------------ | ------------------------------------------------------- |
| SO                 | Ubuntu 22.04 LTS (limpio)                               |
| Acceso             | SSH root o usuario sudo                                 |
| Panel              | HestiaCP (maneja firewall iptables)                     |
| Node.js            | Plugin oficial / nvm                                    |
| Coolify            | Instalación manual en `/data/coolify`                   |
| Requisitos mínimos | 2 vCPU / 4 GB RAM / 40 GB SSD                           |
| Dominio dedicado   | Ejemplo: `panel.midominio.com`, `coolify.midominio.com` |

---

## 1. Acceso y actualización del servidor

```bash
ssh root@your.server
apt update && apt upgrade -y
```

Configura hostname y zona horaria:

```bash
hostnamectl set-hostname vps-hestia
timedatectl set-timezone America/Costa_Rica         # Ejemplo con Costa Rica
```

---

## 2. Instalación de HestiaCP

### 2.1 Descargar script

```bash
wget https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh
chmod +x hst-install.sh
```

### 2.2 Ejecutar instalación recomendada

```bash
bash hst-install.sh --multiphp '7.4,8.0,8.1,8.2,8.3,8.4' --quota yes --webterminal yes
```

Durante la instalación:

* Define hostname → `panel.midominio.com`
* Email del administrador
* Activa servicios recomendados: **nginx + php-fpm + mariadb + fail2ban + firewall**

> ⚙️ Hestia instalará y configurará automáticamente iptables, por lo tanto **no instales ni modifiques iptables manualmente**.

---

## 3. Validar Hestia

Acceder al panel:

```
https://<IP_o_dominio>:8083
```

Comprobar servicios:

```bash
systemctl status hestia nginx php8.1-fpm
```

---

## 4. Instalar Node.js (Plugin Hestia)

### 4.1 Instalar Node.js base

```bash
# Download and install nvm:
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

# in lieu of restarting the shell
\. "$HOME/.nvm/nvm.sh"

# Download and install Node.js:
nvm install 24
```

Verificar:

```bash
node -v
npm -v
```

### 4.2 Instalar PM2
```bash
npm install pm2 -g
```

Verificar:

```bash
pm2 -v
```

### 4.3 Integrar con Hestia

Instala el plugin Node.js (comunitario):
```bash
# Clona el respositorio
cd ~/tmp
git clone https://github.com/JLFdzDev/hestiacp-nodejs.git
cd hestiacp-nodejs

# Ejecuta la instalacion
sudo chmod 755 install.sh
sudo ./install.sh
```

Ahora podrás crear aplicaciones Node.js desde Hestia (por usuario web).

---

## 5. Instalar Docker (requerido por Coolify)

> **Nota:** Hestia maneja el firewall, no ajustes puertos manualmente.

```bash
# Add Docker's official GPG key:
apt-get update
apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Instalar docker
sudo apt update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Habilitar servicio de docker
systemctl enable docker
systemctl start docker
```

Verificar:

```bash
docker --version
docker compose version
```

---

## 6. Instalación manual de Coolify

### 6.1 Crear directorios base

```bash
mkdir -p /data/coolify/{source,ssh,applications,databases,backups,services,proxy,webhooks-during-maintenance}
mkdir -p /data/coolify/ssh/{keys,mux}
mkdir -p /data/coolify/proxy/dynamic
```

### 6.2 Generar y registrar clave SSH

```bash
ssh-keygen -f /data/coolify/ssh/keys/id.root@host.docker.internal -t ed25519 -N '' -C root@coolify
cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```


### 6.3 Descargar archivos fuente de Coolify

```bash
curl -fsSL https://cdn.coollabs.io/coolify/docker-compose.yml -o /data/coolify/source/docker-compose.yml
curl -fsSL https://cdn.coollabs.io/coolify/docker-compose.prod.yml -o /data/coolify/source/docker-compose.prod.yml
curl -fsSL https://cdn.coollabs.io/coolify/.env.production -o /data/coolify/source/.env
curl -fsSL https://cdn.coollabs.io/coolify/upgrade.sh -o /data/coolify/source/upgrade.sh
```

### 6.4 Permisos correctos

```bash
chown -R 9999:root /data/coolify
chmod -R 700 /data/coolify
```


### 6.5 Generar valores únicos en `.env`

```bash
sed -i "s|APP_ID=.*|APP_ID=$(openssl rand -hex 16)|g" /data/coolify/source/.env
sed -i "s|APP_KEY=.*|APP_KEY=base64:$(openssl rand -base64 32)|g" /data/coolify/source/.env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$(openssl rand -base64 32)|g" /data/coolify/source/.env
sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=$(openssl rand -base64 32)|g" /data/coolify/source/.env
sed -i "s|PUSHER_APP_ID=.*|PUSHER_APP_ID=$(openssl rand -hex 32)|g" /data/coolify/source/.env
sed -i "s|PUSHER_APP_KEY=.*|PUSHER_APP_KEY=$(openssl rand -hex 32)|g" /data/coolify/source/.env
sed -i "s|PUSHER_APP_SECRET=.*|PUSHER_APP_SECRET=$(openssl rand -hex 32)|g" /data/coolify/source/.env
```

> ⚠️ Ejecuta estos comandos **solo una vez**.
> Cambiar estos valores posteriormente rompe la instalación.


### 6.6 Crear red Docker

```bash
docker network create --attachable coolify
```


### 6.8 Iniciar Coolify

```bash
docker compose --env-file /data/coolify/source/.env \
  -f /data/coolify/source/docker-compose.yml \
  -f /data/coolify/source/docker-compose.prod.yml \
  up -d --pull always --remove-orphans --force-recreate
```

Verificar contenedores:

```bash
docker ps
```

Coolify ahora corre en `http://<IP>:8000`

---

## 7. Integrar Coolify con Hestia (Proxy inverso + SSL)

HestiaCP permite definir plantillas personalizadas de Nginx para manejar aplicaciones que corren en otros puertos o servicios locales, como **Coolify**, **Node.js apps**, o cualquier dashboard Dockerizado.
Esta integración se basa en la creación de plantillas en:

```
/usr/local/hestia/data/templates/web/nginx/
```

---

### 7.1 Crear las plantillas proxy personalizadas

#### Archivos necesarios

Crea los siguientes archivos (como root):

**Coolify (puerto 8000 + servicios en 6001 / 6002)**
Ruta:

```
/usr/local/hestia/data/templates/web/nginx/coolify_proxy.tpl
/usr/local/hestia/data/templates/web/nginx/coolify_proxy.stpl
```

Contenido:
- **coolify_proxy.tpl (HTTP):**

```nginx
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

    # --- COOLIFY DASHBOARD ---
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

    # --- REAL-TIME SERVICE (puerto 6001) ---
    location /app/ {
        proxy_pass http://127.0.0.1:6001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }

    # --- TERMINAL SERVICE (puerto 6002) ---
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
```

- **coolify_proxy.stpl (HTTPS):**

```nginx
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

    # --- COOLIFY DASHBOARD ---
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

    # --- REAL-TIME SERVICE (puerto 6001) ---
    location /app/ {
        proxy_pass http://127.0.0.1:6001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }

    # --- TERMINAL SERVICE (puerto 6002) ---
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
```


### 7.2 Asignar la plantilla en el dominio

1. Entra al panel **Hestia → Web → Add Domain**

   * Dominio: `coolify.midominio.com`
   * SSL desactivado (se habilitará luego)
2. Edita el dominio recién creado.
3. En **Web Template (Nginx)** selecciona:
   `coolify_proxy`
4. Guarda los cambios.


### 7.3 Activar SSL (Let's Encrypt)

Regresa a **Web → Edit Domain → SSL** y activa:

* ✅ SSL Support
* ✅ Let's Encrypt Support

Guarda los cambios.
Esto generará automáticamente certificados válidos y aplicará la versión `.stpl` de la plantilla.


### 7.4 Validar acceso

Abre en navegador:
`https://coolify.midominio.com`

Deberías ver el dashboard de **Coolify**, completamente accesible a través de Hestia, con tráfico HTTPS y servicios websocket funcionales.


---

## 8 Configurar dominio o subdominio funcional para Coolify (Traefik Proxy)

Coolify utiliza un **proxy interno basado en Traefik** que enruta las aplicaciones y servicios desplegados dentro de su entorno Docker.
Para exponer correctamente este proxy hacia Internet, se recomienda asignar un **dominio o subdominio dedicado**, por ejemplo:

* **Dominio completo:** `midominio.com`
* **Subdominio dedicado:** `proxy.midominio.com`

Ambas opciones son válidas, siempre que se configure correctamente el **alias wildcard (`*.midominio.com`)** y el correspondiente registro DNS.


### 8.1 Plantillas personalizadas para el proxy Traefik

Crea las plantillas Nginx que actuarán como proxy inverso hacia el contenedor Traefik (puerto 8001), que Coolify usa internamente.

Rutas:

```
/usr/local/hestia/data/templates/web/nginx/coolify-subdomain_proxy.tpl
/usr/local/hestia/data/templates/web/nginx/coolify-subdomain_proxy.stpl
```

Contenido:
- **coolify-subdomain_proxy.tpl (HTTP):**

```nginx
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

    # --- PROXY HTTP (Traefik, puerto 8001) ---
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
```

- **coolify-subdomain_proxy.stpl (HTTPS):**

```nginx
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

    # --- PROXY HTTPS (Traefik, puerto 8001) ---
    location / {
        proxy_pass http://127.0.0.1:8001;
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
```

Guarda ambos archivos.


### 8.2 Crear dominio o subdominio en Hestia

1. En el panel **HestiaCP → Web → Add Domain**

   * Ingresa el dominio o subdominio que se usará con Coolify
     (por ejemplo `proxy.midominio.com` o `midominio.com`)
   * Desactiva temporalmente SSL.

2. Edita el dominio y selecciona:

   * **Web Template (Nginx):** `coolify-subdomain_proxy`

3. En el campo **Aliases**, agrega el comodín (`*`) correspondiente:

   ```
   *.midominio.com
   ```

   Esto permitirá que Coolify genere subdominios dinámicos para las aplicaciones.

4. Guarda los cambios.


### 8.3 Configurar DNS para el alias wildcard

En tu panel DNS (ya sea el propio Hestia o tu proveedor externo), agrega los siguientes registros:

| Tipo               | Nombre  | Valor / Destino     | Descripción                       |
| ------------------ | ------- | ------------------- | --------------------------------- |
| **A**              | `@`     | IP del servidor VPS | Dominio raíz                      |
| **A**              | `*`     | IP del servidor VPS | Permite subdominios dinámicos     |

**Ejemplo:**

```
midominio.com     → 192.168.1.10
*.midominio.com   → 192.168.1.10
```

**Importante:**
Si usas un *wildcard SSL certificate* (`*.midominio.com`), Let’s Encrypt **solo admite validación DNS**. HestiaCP lo gestiona automaticamente por lo que el DNS debe ser manejado por este mismo.


### 8.4 Activar SSL con Let’s Encrypt

1. En **Web → Edit Domain → SSL**:

   * Activa **SSL Support**
   * Activa **Let’s Encrypt Support**

2. Finaliza el proceso desde Hestia y confirma que el certificado fue emitido correctamente.

Resultado:

```
https://midominio.com
https://*.midominio.com (Ej: https://app1.midominio.com)
```

Todos responderán vía el proxy Traefik interno.


### 8.5 Configurar Coolify para usar el dominio

En el panel de Coolify:

1. Ir a:

   ```
   Servers → localhost → Configuration → General
   ```
2. En el campo **Wildcard Domain**, establecer el dominio raíz o subdominio principal:

   ```
   midominio.com
   ```

   o bien:

   ```
   proxy.midominio.com
   ```

   según el dominio que elegiste.

Esto permitirá que Coolify gestione automáticamente los certificados y subdominios de las aplicaciones.



### 8.6 Configurar y activar el proxy interno (Traefik)

1. Ir a:

   ```
   Servers → localhost → Proxy → Configuration
   ```

2. Modifica la configuracion compose de Traefik:

   ```
   name: coolify-proxy
    networks:
      coolify:
        external: true
    services:
      traefik:
        container_name: coolify-proxy
        image: 'traefik:v3.1'
        restart: unless-stopped
        extra_hosts:
          - 'host.docker.internal:host-gateway'
        networks:
          - coolify
        ports:
          - '8001:80'
          - '8002:443'
          - '8002:443/udp'
          - '8003:8080'
        healthcheck:
          test: 'wget -qO- http://localhost:80/ping || exit 1'
          interval: 4s
          timeout: 2s
          retries: 5
        volumes:
          - '/var/run/docker.sock:/var/run/docker.sock:ro'
          - '/data/coolify/proxy/:/traefik'
        command:
          - '--ping=true'
          - '--ping.entrypoint=http'
          - '--api.dashboard=true'
          - '--entrypoints.http.address=:80'
          - '--entrypoints.https.address=:443'
          - '--entrypoints.http.forwardedHeaders.trustedIPs=0.0.0.0/0'
          - '--entrypoints.https.forwardedHeaders.trustedIPs=0.0.0.0/0'
          - '--entrypoints.http.http.encodequerysemicolons=true'
          - '--entryPoints.http.http2.maxConcurrentStreams=250'
          - '--entrypoints.https.http.encodequerysemicolons=true'
          - '--entryPoints.https.http2.maxConcurrentStreams=250'
          - '--entrypoints.https.http3'
          - '--providers.file.directory=/traefik/dynamic/'
          - '--providers.file.watch=true'
          - '--certificatesresolvers.letsencrypt.acme.httpchallenge=true'
          - '--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=http'
          - '--certificatesresolvers.letsencrypt.acme.storage=/traefik/acme.json'
          - '--api.insecure=false'
          - '--providers.docker=true'
          - '--providers.docker.exposedbydefault=false'
        labels:
          - traefik.enable=true
          - traefik.http.routers.traefik.entrypoints=http
          - traefik.http.routers.traefik.service=api@internal
          - traefik.http.services.traefik.loadbalancer.server.port=8080
          - coolify.managed=true
          - coolify.proxy=true
   ```

3. Aplica y reinicia el proxy.


### 8.7 Verificación final

* Accede a:

  ```
  https://{dominio-proxy}
  ```

  Debes ver o el dominio correspondiente (si ya desplegaste alguna app) o un error 404 de Traefik.

* Verifica que los contenedores estén corriendo:

  ```bash
  docker ps | grep traefik
  ```

* Desde Coolify, despliega una aplicación con dominio `app1.midominio.com`.
  Si el wildcard DNS y SSL están configurados, el subdominio se resolverá y certificará automáticamente.

---

## 9. Verificación general

```bash
# Estado de servicios
systemctl status hestia nginx docker

# Contenedores activos
docker ps

# Puertos activos
ss -tuln | grep -E "80|443|8083|8000|8001|8002|6001|6002"

# Logs de coolify
docker logs $(docker ps -qf "name=coolify")

# Logs del proxy de coolify
docker logs $(docker ps -qf "name=coolify-proxy")
```

---

## 10. Respaldos y restauración

| Elemento       | Ubicación                                | Método                                          |
| -------------- | ---------------------------------------- | ----------------------------------------------- |
| HestiaCP       | `/backup/`                               | Backups automáticos desde panel                 |
| Bases de datos | `/backup/`                               | Backups automáticos desde panel                 |
| Coolify        | `/data/coolify`                          | `tar -czvf coolify-backup.tar.gz /data/coolify` |
| Node.js apps   | `/home/usuario/web/`                     | Respaldos de código y `.env`                    |

Backup automatico de coolify:
```
0 3 * * * tar -czf /backup/coolify-$(date +\%F).tar.gz /data/coolify --exclude=/data/coolify/logs
```

Restaurar:

1. Instalar Hestia y Docker.
2. Extraer `/data/coolify` y levantar con `docker compose`.
3. Restaurar backups Hestia desde panel.

---

## 11. Checklist de despliegue

Utiliza esta lista de control para confirmar que el entorno está correctamente replicado y funcional:

| # | Componente                                     | Estado | Detalles                                              |
| - | ---------------------------------------------- | ------ | ----------------------------------------------------- |
| 1 | VPS Ubuntu 22.04 (o superior)                  | ☐      | Instalación base limpia con acceso SSH root           |
| 2 | HestiaCP instalado y actualizado               | ☐      | Panel accesible en puerto 8083                        |
| 3 | Node.js plugin activo                          | ☐      | Disponible para ejecutar apps o servicios auxiliares  |
| 4 | Docker y Docker Compose 24+ instalados         | ☐      | Verificado con `docker --version`                     |
| 5 | Coolify desplegado en `/data/coolify`          | ☐      | Contenedores activos (`coolify`, `coolify-proxy`)     |
| 6 | Red Docker `coolify` creada                    | ☐      | Confirmado con `docker network ls`                    |
| 7 | Proxy inverso Nginx (Hestia) configurado       | ☐      | Plantillas `coolify_proxy.tpl` y `.stpl` aplicadas   |
| 8 | Dominio/subdominio dedicado para Coolify       | ☐      | Ejemplo: `proxy.midominio.com`                        |
| 9 | Alias wildcard configurado (`*.midominio.com`) | ☐      | DNS apunta al servidor Hestia                         |
| 10 | Let’s Encrypt emitido por validación DNS       | ☐      | Certificados activos para wildcard                    |
| 11 | Coolify Proxy (Traefik) operativo              | ☐      | Puertos 8001–8003 accesibles localmente               |
| 12 | SSL activo y verificado en navegador           | ☐      | Acceso vía `https://proxy.midominio.com`              |
| 13 | Backups automáticos configurados               | ☐      | Revisar tareas de Hestia y Coolify                    |
| 14 | Despliegue de prueba exitoso                   | ☐      | Aplicación `hello world` accesible por subdominio     |
| 15 | Seguridad básica aplicada                      | ☐      | Fail2Ban, cortafuegos Hestia y actualizaciones al día |



Perfecto 👍 — aquí tienes una **sección adicional de anexo**, lista para incorporar en tu documentación técnica, que explica cómo crear y aplicar **un proxy inverso genérico con HestiaCP**, usando plantillas personalizadas Nginx (como tu ejemplo `streamvision-proxy.tpl / stpl`).

---

## Anexo: Creación de Proxy Inverso Personalizado en HestiaCP

Esta sección explica cómo crear una plantilla Nginx personalizada en HestiaCP para **proxificar cualquier servicio o aplicación externa** (por IP, dominio o puerto), ideal para exponer dashboards, APIs, contenedores o servicios en red interna.

### 1. Ubicación de plantillas

Las plantillas de Nginx se almacenan en:

```bash
/usr/local/hestia/data/templates/web/nginx/
```

Cada plantilla debe tener **dos versiones**:

* `.tpl` → para tráfico **HTTP (puerto 80)**
* `.stpl` → para tráfico **HTTPS (puerto 443)**

### 2. Ejemplo de plantilla: `yourapp_proxy`

#### Archivo: `/usr/local/hestia/data/templates/web/nginx/yourapp_proxy.tpl`

```nginx
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

    # --- PROXY HTTP ---
    location / {
        proxy_pass http://{DEST_IP}:{DEST_PORT}; # IP o dominio destino y su puerto
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;

        # Reescribe URLs internas (opcional)
        sub_filter 'https://streamvision.webcr.top' 'http://streamvision.webcr.top';
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
```

#### Archivo: `/usr/local/hestia/data/templates/web/nginx/yourapp_proxy.stpl`

```nginx
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

    # --- PROXY HTTPS ---
    location / {
        proxy_pass http://{DEST_IP}:{DEST_PORT}; # IP o dominio destino y su puerto
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;

        add_header 'Content-Security-Policy' 'upgrade-insecure-requests';

        # Reescribe URLs internas (opcional)
        sub_filter 'http://streamvision.webcr.top' 'https://streamvision.webcr.top';
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
```


### 3. Activar la plantilla en HestiaCP

1. Inicia sesión en el panel Hestia (`https://IP-SERVIDOR:8083`)
2. Ve a **Web → Editar dominio**
3. En **Web Template → Nginx**, selecciona la nueva plantilla `yourapp_proxy`
4. Guarda los cambios
5. (Opcional) Activa SSL:

   * ✅ **SSL Support**
   * ✅ **Let's Encrypt Support**

Hestia regenerará automáticamente el archivo de configuración del dominio con el nuevo proxy.


### 4. Verificación

```bash
nginx -t
systemctl reload nginx
```

Luego accede al dominio configurado, por ejemplo:

```
https://midominio.com
```


### 5. Parámetros útiles de proxy

| Directiva                            | Descripción                                          |
| ------------------------------------ | ---------------------------------------------------- |
| `proxy_pass`                         | Dirección de destino (IP o dominio)                  |
| `sub_filter`                         | Reescribe contenido HTML con URLs internas           |
| `proxy_buffering off`                | Desactiva buffering (útil para streams o websockets) |
| `proxy_http_version 1.1` + `Upgrade` | Necesario para WebSockets                            |
| `proxy_intercept_errors on`          | Permite manejar errores HTTP en Nginx                |


### Tip adicional

Si necesitas proxificar **servicios internos o en Docker**, usa `localhost` o `127.0.0.1` con su puerto correspondiente.
Ejemplo:

```nginx
proxy_pass http://127.0.0.1:3000; # App Node.js
```

Y si el destino usa HTTPS interno con certificado autofirmado:

```nginx
proxy_ssl_verify off;
```
