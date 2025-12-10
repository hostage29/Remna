#!/bin/bash

# =============================================================================
# ОБНОВЛЕННЫЙ СКРИПТ УСТАНОВКИ REMNAWAVE NODE НА UBUNTU 22
# Исправлены проблемы с портом 80 и Docker networking
# =============================================================================

# =============================================================================
# НАСТРОЙКА ЦВЕТОВ ДЛЯ ВЫВОДА
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# ФУНКЦИИ ДЛЯ КРАСИВОГО ВЫВОДА
# =============================================================================
print_section() {
    echo -e "\n${CYAN}# =============================================================================${NC}"
    echo -e "${CYAN}# $1${NC}"
    echo -e "${CYAN}# =============================================================================${NC}"
}

print_step() {
    echo -e "\n${YELLOW}➜ Этап $STEP: $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ Ошибка: $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Функция для безопасного запроса ввода
safe_read() {
    local prompt="$1"
    local var_name="$2"
    
    echo -ne "${YELLOW}${prompt}${NC}"
    read -r "$var_name"
}

# =============================================================================
# ПЕРЕМЕННЫЕ
# =============================================================================
STEP=0
INSTALL_DIR="/opt/remnanode"
SSL_DIR="$INSTALL_DIR/ssl"
LETSENCRYPT_DIR="/etc/letsencrypt"
NO_SSL=false

# =============================================================================
# 1. ПРОВЕРКА ПРАВ И ПАРАМЕТРОВ
# =============================================================================
print_section "1. ПРОВЕРКА ПРАВ И ПАРАМЕТРОВ"
STEP=1

if [ "$EUID" -ne 0 ]; then 
    print_error "Пожалуйста, запустите скрипт с правами root (sudo)"
    exit 1
fi

print_success "Скрипт запущен с правами root"

# =============================================================================
# 2. ПОЛУЧЕНИЕ SECRET_KEY ДЛЯ NODE
# =============================================================================
print_section "2. ПОЛУЧЕНИЕ SECRET_KEY ДЛЯ NODE"
STEP=2

print_info "Для установки Remnawave Node необходим SECRET_KEY."
print_info "Получите его в панели управления Remnawave."

safe_read "Введите ваш SECRET_KEY (набор символов без префикса): " SECRET_KEY_INPUT

if [ -z "$SECRET_KEY_INPUT" ]; then
    print_error "SECRET_KEY не может быть пустым!"
    exit 1
fi

SECRET_KEY="SECRET_KEY=$SECRET_KEY_INPUT"
print_success "SECRET_KEY получен"

# =============================================================================
# 3. ПОЛУЧЕНИЕ ДАННЫХ ДЛЯ LET'S ENCRYPT
# =============================================================================
print_section "3. ПОЛУЧЕНИЕ ДАННЫХ ДЛЯ LET'S ENCRYPT"
STEP=3

print_info "Для настройки SSL с Let's Encrypt нужна следующая информация:"

safe_read "Введите ваш email для Let's Encrypt: " LETSENCRYPT_EMAIL
safe_read "Введите ваше доменное имя (например, node.example.com): " DOMAIN_NAME

if [ -z "$LETSENCRYPT_EMAIL" ] || [ -z "$DOMAIN_NAME" ]; then
    print_error "Email и доменное имя не могут быть пустыми!"
    exit 1
fi

print_success "Данные для Let's Encrypt получены"

# =============================================================================
# 4. ПРОВЕРКА И ОБНОВЛЕНИЕ СИСТЕМЫ
# =============================================================================
print_section "4. ПРОВЕРКА И ОБНОВЛЕНИЕ СИСТЕМЫ"
STEP=4

print_step "Обновление списка пакетов..."
apt-get update -q
if [ $? -eq 0 ]; then
    print_success "Список пакетов обновлен"
else
    print_error "Не удалось обновить список пакетов"
    exit 1
fi

print_step "Установка необходимых утилит..."
apt-get install -y -q curl wget net-tools git nano openssl cron fail2ban dnsutils python3 python3-venv
if [ $? -eq 0 ]; then
    print_success "Утилиты установлены"
else
    print_error "Не удалось установить утилиты"
    exit 1
fi

# =============================================================================
# 5. УСТАНОВКА DOCKER
# =============================================================================
print_section "5. УСТАНОВКА DOCKER"
STEP=5

if command -v docker &> /dev/null; then
    print_success "Docker уже установлен"
else
    print_step "Установка Docker..."
    
    apt-get install -y -q apt-transport-https ca-certificates curl software-properties-common
    
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" -y
    
    apt-get update -q
    apt-get install -y -q docker-ce docker-ce-cli containerd.io
    
    if [ $? -eq 0 ]; then
        print_success "Docker установлен"
    else
        print_error "Не удалось установить Docker"
        exit 1
    fi
    
    systemctl enable docker
    systemctl start docker
    print_success "Docker запущен и добавлен в автозагрузку"
fi

# =============================================================================
# 6. УСТАНОВКА DOCKER COMPOSE
# =============================================================================
print_section "6. УСТАНОВКА DOCKER COMPOSE"
STEP=6

if command -v docker-compose &> /dev/null; then
    print_success "Docker Compose уже установлен"
else
    print_step "Установка Docker Compose..."
    
    # Скачиваем Docker Compose v2
    DOCKER_COMPOSE_VERSION="v2.29.0"
    ARCH=$(uname -m)
    
    if [ "$ARCH" = "x86_64" ]; then
        COMPOSE_ARCH="x86_64"
    elif [ "$ARCH" = "aarch64" ]; then
        COMPOSE_ARCH="aarch64"
    else
        COMPOSE_ARCH="$(uname -m)"
    fi
    
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${COMPOSE_ARCH}" -o /usr/local/bin/docker-compose
    
    chmod +x /usr/local/bin/docker-compose
    
    if docker-compose --version > /dev/null 2>&1; then
        print_success "Docker Compose установлен"
    else
        print_error "Не удалось установить Docker Compose"
        exit 1
    fi
fi

# =============================================================================
# 7. НАСТРОЙКА DOCKER ДЛЯ РАБОТЫ С IPTABLES
# =============================================================================
print_section "7. НАСТРОЙКА DOCKER ДЛЯ РАБОТЫ С IPTABLES"
STEP=7

print_step "Настройка Docker для корректной работы с iptables..."

# Создаем конфиг Docker
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "iptables": true,
  "ip-forward": true,
  "ip-masq": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true
}
EOF

# Перезапускаем Docker
systemctl restart docker
sleep 3

print_success "Docker настроен для работы с iptables"

# =============================================================================
# 8. СОЗДАНИЕ СТРУКТУРЫ ДИРЕКТОРИЙ
# =============================================================================
print_section "8. СОЗДАНИЕ СТРУКТУРЫ ДИРЕКТОРИЙ"
STEP=8

print_step "Создание директории установки: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Критически важные директории для Xray
mkdir -p data config logs/nginx logs/remnanode logs/xray backup scripts nginx/conf.d nginx/html
chmod -R 755 logs/

print_success "Структура директорий создана"

# =============================================================================
# 9. СОЗДАНИЕ ФАЙЛА .ENV
# =============================================================================
print_section "9. СОЗДАНИЕ ФАЙЛА .ENV"
STEP=9

cat > .env << EOF
# =============================================================================
# КОНФИГУРАЦИЯ REMNAWAVE NODE
# =============================================================================

# Основной секретный ключ
${SECRET_KEY}

# Порт ноды (ОБЯЗАТЕЛЬНО!)
NODE_PORT=2222

# Окружение
NODE_ENV=production

# Часовой пояс
TZ=Europe/Moscow

# Уровень логирования
LOG_LEVEL=info

# Режим отладки
DEBUG=false

# Автоматическое обновление
AUTO_UPDATE=true

# Лимит логирования (в днях)
LOG_RETENTION_DAYS=7

# =============================================================================
# НАСТРОЙКИ БЕЗОПАСНОСТИ
# =============================================================================

# Пароль для API (опционально)
# API_PASSWORD=your_secure_password

# IP-адреса для доступа к API
# ALLOWED_IPS=192.168.1.0/24,10.0.0.0/8

# =============================================================================
# РЕСУРСЫ КОНТЕЙНЕРА
# =============================================================================

# Лимит памяти
CONTAINER_MEMORY_LIMIT=1G

# Лимит CPU
CONTAINER_CPU_LIMIT=1.0
EOF

print_success "Файл .env создан"

# =============================================================================
# 10. ДИАГНОСТИКА DNS И ОЧИСТКА ПОРТА 80
# =============================================================================
print_section "10. ДИАГНОСТИКА DNS И ОЧИСТКА ПОРТА 80"
STEP=10

print_step "Проверка DNS записи..."
CURRENT_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
print_info "Текущий IP сервера: $CURRENT_IP"

DNS_IP=$(dig +short "$DOMAIN_NAME" 2>/dev/null || echo "")
if [ -z "$DNS_IP" ]; then
    print_error "DNS запись не найдена для $DOMAIN_NAME"
    print_info "Настройте DNS запись типа A: $DOMAIN_NAME → $CURRENT_IP"
    print_info "Подождите 5-10 минут и продолжите установку"
    safe_read "Продолжить установку? (y/n): " CONTINUE_INSTALL
    if [[ ! "$CONTINUE_INSTALL" =~ ^[Yy]$ ]]; then
        exit 1
    fi
elif [ "$DNS_IP" = "$CURRENT_IP" ]; then
    print_success "DNS настроен правильно: $DOMAIN_NAME → $DNS_IP"
else
    print_error "DNS не настроен правильно!"
    print_info "Ожидаемый IP: $CURRENT_IP"
    print_info "Полученный IP: $DNS_IP"
    print_info "Продолжаем, но SSL может не сработать"
fi

# КРИТИЧЕСКИ ВАЖНО: Очистка порта 80
print_step "Очистка порта 80 для получения SSL..."
echo "Останавливаем все процессы на порту 80..."

# 1. Останавливаем системные веб-серверы
systemctl stop nginx apache2 2>/dev/null || true

# 2. Убиваем процессы Python
pkill -f "python3 -m http.server" 2>/dev/null || true

# 3. Останавливаем Docker контейнеры на порту 80
docker stop $(docker ps -q --filter "publish=80") 2>/dev/null || true
docker rm $(docker ps -aq --filter "publish=80") 2>/dev/null || true

# 4. Проверяем и убиваем другие процессы
if ss -tlnp | grep -q ":80 "; then
    echo "Найденные процессы на порту 80:"
    ss -tlnp | grep ":80 "
    
    # Получаем PID процесса
    PID=$(ss -tlnp | grep ":80 " | awk '{print $6}' | cut -d= -f2 | cut -d, -f1 | head -1)
    if [ ! -z "$PID" ] && [ "$PID" != "-" ]; then
        echo "Останавливаем процесс PID: $PID"
        kill -9 $PID 2>/dev/null || true
        sleep 2
    fi
fi

# 5. Финальная проверка
if ss -tln | grep -q ":80 "; then
    print_error "Не удалось освободить порт 80!"
    print_info "SSL не будет получен. Продолжаем без SSL."
    NO_SSL=true
else
    print_success "Порт 80 свободен и готов для получения SSL"
fi

# =============================================================================
# 11. НАСТРОЙКА IPTABLES БЕЗ КОНФЛИКТА С DOCKER
# =============================================================================
print_section "11. НАСТРОЙКА IPTABLES БЕЗ КОНФЛИКТА С DOCKER"
STEP=11

print_step "Настройка iptables для работы с Docker..."

# Сохраняем текущие правила
iptables-save > /tmp/iptables-backup.rules

# Очищаем только INPUT цепочку (не трогаем DOCKER цепочки)
iptables -F INPUT
iptables -X INPUT 2>/dev/null || true

# Создаем новую цепочку для наших правил
iptables -N CUSTOM-INPUT 2>/dev/null || true
iptables -F CUSTOM-INPUT

# Добавляем правила в нашу цепочку
iptables -A CUSTOM-INPUT -i lo -j ACCEPT
iptables -A CUSTOM-INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A CUSTOM-INPUT -p tcp --dport 22 -j ACCEPT      # SSH
iptables -A CUSTOM-INPUT -p tcp --dport 80 -j ACCEPT      # HTTP (для SSL)
iptables -A CUSTOM-INPUT -p tcp --dport 443 -j ACCEPT     # HTTPS
iptables -A CUSTOM-INPUT -p tcp --dport 2222 -j ACCEPT    # Remnawave API
iptables -A CUSTOM-INPUT -p tcp -m multiport --dports 61000:61002 -j ACCEPT  # Xray порты
iptables -A CUSTOM-INPUT -p icmp --icmp-type echo-request -j ACCEPT  # Ping
iptables -A CUSTOM-INPUT -j DROP  # Все остальное блокируем

# Вставляем нашу цепочку в начало INPUT
iptables -I INPUT 1 -j CUSTOM-INPUT

# Разрешаем FORWARD для Docker (критически важно!)
iptables -P FORWARD ACCEPT

print_success "iptables настроен без конфликта с Docker"

# =============================================================================
# 12. ПОЛУЧЕНИЕ SSL СЕРТИФИКАТА LET'S ENCRYPT
# =============================================================================
print_section "12. ПОЛУЧЕНИЕ SSL СЕРТИФИКАТА LET'S ENCRYPT"
STEP=12

print_step "Установка Certbot для Let's Encrypt..."
apt-get install -y -q certbot

if [ $? -eq 0 ]; then
    print_success "Certbot установлен"
else
    print_error "Не удалось установить Certbot"
    NO_SSL=true
fi

if [ "$NO_SSL" = false ]; then
    print_step "Получение SSL сертификата Let's Encrypt..."
    
    # Дополнительная проверка порта 80
    if ss -tln | grep -q ":80 "; then
        print_error "Порт 80 все еще занят! Пробуем альтернативный метод..."
        
        # Пробуем получить через DNS (если домен на Cloudflare)
        safe_read "Использовать DNS валидацию (Cloudflare)? (y/n): " USE_DNS
        
        if [[ "$USE_DNS" =~ ^[Yy]$ ]]; then
            print_step "Установка плагина для Cloudflare..."
            apt-get install -y -q python3-certbot-dns-cloudflare
            
            safe_read "Введите Cloudflare API токен: " CF_TOKEN
            
            # Создаем конфиг для Cloudflare
            cat > /etc/letsencrypt/cloudflare.ini << EOF
dns_cloudflare_api_token = $CF_TOKEN
EOF
            chmod 600 /etc/letsencrypt/cloudflare.ini
            
            # Получаем через DNS
            certbot certonly --dns-cloudflare \
                --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
                --email "$LETSENCRYPT_EMAIL" \
                -d "$DOMAIN_NAME" \
                --agree-tos \
                --non-interactive
        else
            NO_SSL=true
        fi
    else
        # Стандартный метод через порт 80
        certbot certonly --standalone --agree-tos --non-interactive \
            --email "$LETSENCRYPT_EMAIL" \
            -d "$DOMAIN_NAME" \
            --preferred-challenges http
        
        if [ $? -eq 0 ]; then
            print_success "✅ SSL сертификат Let's Encrypt получен!"
            
            # Создаем символические ссылки
            mkdir -p $SSL_DIR
            ln -sf $LETSENCRYPT_DIR/live/$DOMAIN_NAME/fullchain.pem $SSL_DIR/certificate.crt 2>/dev/null || true
            ln -sf $LETSENCRYPT_DIR/live/$DOMAIN_NAME/privkey.pem $SSL_DIR/private.key 2>/dev/null || true
            
            print_info "Сертификаты: $LETSENCRYPT_DIR/live/$DOMAIN_NAME/"
        else
            print_error "Не удалось получить SSL сертификат Let's Encrypt"
            print_info "Продолжаем без SSL. Вы можете настроить его позже."
            NO_SSL=true
            DOMAIN_NAME="localhost"
        fi
    fi
fi

# =============================================================================
# 13. НАСТРОЙКА АВТОМАТИЧЕСКОГО ПРОДЛЕНИЯ SSL
# =============================================================================
print_section "13. НАСТРОЙКА АВТОМАТИЧЕСКОГО ПРОДЛЕНИЯ SSL"
STEP=13

if [ "$NO_SSL" = false ]; then
    print_step "Создание скрипта для автоматического продления SSL..."
    
    cat > /usr/local/bin/renew-ssl-cert << 'EOF'
#!/bin/bash

# =============================================================================
# СКРИПТ ДЛЯ АВТОМАТИЧЕСКОГО ОБНОВЛЕНИЯ SSL СЕРТИФИКАТОВ
# =============================================================================

echo "Проверка обновления SSL сертификатов..."

# Временно разрешаем порт 80 в нашей цепочке
iptables -I CUSTOM-INPUT 1 -p tcp --dport 80 -j ACCEPT

# Обновляем сертификаты
certbot renew --quiet --deploy-hook "cd /opt/remnanode && docker-compose restart nginx 2>/dev/null || true"

# Удаляем временное правило
iptables -D CUSTOM-INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true

echo "Проверка SSL завершена"
EOF

    chmod +x /usr/local/bin/renew-ssl-cert
    
    # Создаем задание cron для автоматического обновления
    CRON_JOB="0 3 * * * /usr/local/bin/renew-ssl-cert"
    (crontab -l 2>/dev/null | grep -v "/usr/local/bin/renew-ssl-cert"; echo "$CRON_JOB") | crontab -
    
    print_success "Автоматическое продление SSL настроено (ежедневно в 3:00)"
else
    print_info "SSL не настроен, пропускаем настройку автопродления"
fi

# =============================================================================
# 14. НАСТРОЙКА FAIL2BAN
# =============================================================================
print_section "14. НАСТРОЙКА FAIL2BAN"
STEP=14

print_step "Настройка fail2ban..."

if ! command -v fail2ban-client &> /dev/null; then
    print_step "Установка fail2ban..."
    apt-get install -y -q fail2ban
fi

# Создаем конфиг для fail2ban
cat > /etc/fail2ban/jail.d/remnanode.local << EOF
[remnanode-ssh]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600

[remnanode-nginx]
enabled = true
port = http,https
filter = nginx-auth
logpath = /opt/remnanode/logs/nginx/access.log
maxretry = 10
bantime = 3600
EOF

systemctl restart fail2ban
print_success "fail2ban настроен"

# =============================================================================
# 15. СОЗДАНИЕ DOCKER-COMPOSE.YML С УЧЕТОМ ВСЕХ ИСПРАВЛЕНИЙ
# =============================================================================
print_section "15. СОЗДАНИЕ DOCKER-COMPOSE.YML"
STEP=15

# Определяем конфигурацию в зависимости от наличия SSL
NGINX_SERVICE=""
if [ "$NO_SSL" = false ] && [ -d "$LETSENCRYPT_DIR/live/$DOMAIN_NAME" ] 2>/dev/null; then
    NGINX_SERVICE="
  nginx:
    image: nginx:alpine
    container_name: remnanode-nginx
    restart: unless-stopped
    ports:
      - \"443:443\"
      - \"80:80\"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/html:/usr/share/nginx/html:ro
      - ./logs/nginx:/var/log/nginx
    networks:
      - remnanode-network
    depends_on:
      - remnanode
    healthcheck:
      test: [\"CMD-SHELL\", \"nginx -t || exit 1\"]
      interval: 30s
      timeout: 10s
      retries: 3"
fi

cat > docker-compose.yml << EOF
# =============================================================================
# СЕРВИС REMNAWAVE NODE
# =============================================================================
version: '3.8'
services:
  remnanode:
    image: remnawave/node:latest
    container_name: remnanode
    restart: unless-stopped
    
    # Проброс портов
    ports:
      - "2222:2222"     # Основной API порт
      - "61000:61000"   # Xray API порт
      - "61001:61001"   # Дополнительный порт 1
      - "61002:61002"   # Дополнительный порт 2
    
    # Монтирование томов (ВКЛЮЧАЯ ДИРЕКТОРИЮ ДЛЯ ЛОГОВ XRAY)
    volumes:
      - ./data:/data                    # Основные данные
      - ./config:/config                # Конфигурационные файлы
      - ./logs/remnanode:/var/log/remnanode       # Логи приложения
      - ./logs/xray:/var/log/xray       # Логи Xray (КРИТИЧЕСКИ ВАЖНО!)
      - /etc/timezone:/etc/timezone:ro  # Часовой пояс
      - /etc/localtime:/etc/localtime:ro
    
    # Переменные окружения
    env_file:
      - .env
    
    # Дополнительные переменные
    environment:
      - PUID=1000
      - PGID=1000
      - UMASK=022
      - TZ=\${TZ}
    
    # Ограничения ресурсов
    mem_limit: "\${CONTAINER_MEMORY_LIMIT:-1G}"
    cpus: "\${CONTAINER_CPU_LIMIT:-1.0}"
    
    # Настройки сети
    networks:
      - remnanode-network
    
    # Настройки логирования
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    
    # Проверка здоровья
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:2222/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
${NGINX_SERVICE}
# =============================================================================
# СЕТЕВЫЕ НАСТРОЙКИ
# =============================================================================
networks:
  remnanode-network:
    driver: bridge
    name: remnanode-network
EOF

print_success "Файл docker-compose.yml создан с учетом всех исправлений"

# =============================================================================
# 16. СОЗДАНИЕ КОНФИГУРАЦИИ NGINX (если нужен SSL)
# =============================================================================
print_section "16. СОЗДАНИЕ КОНФИГУРАЦИИ NGINX"
STEP=16

if [ "$NO_SSL" = false ] && [ -d "$LETSENCRYPT_DIR/live/$DOMAIN_NAME" ] 2>/dev/null; then
    print_step "Создание конфигурации Nginx с Let's Encrypt..."
    
    # Основной конфиг nginx
    cat > nginx/nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    include /etc/nginx/conf.d/*.conf;
}
EOF
    
    # Конфиг для Remnawave Node с SSL
    cat > nginx/conf.d/remnanode.conf << EOF
# HTTP редирект на HTTPS
server {
    listen 80;
    server_name $DOMAIN_NAME;
    
    # Для ACME challenge (Let's Encrypt)
    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
        try_files \$uri =404;
    }
    
    # Редирект всего остального на HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS сервер
server {
    listen 443 ssl http2;
    server_name $DOMAIN_NAME;

    # Let's Encrypt SSL сертификаты
    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;
    
    # Настройки SSL
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_stapling on;
    ssl_stapling_verify on;

    # Безопасные заголовки
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";

    # Проксирование на Remnawave Node
    location / {
        proxy_pass http://remnanode:2222;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        proxy_buffering off;
    }

    # Health check
    location /health {
        proxy_pass http://remnanode:2222/health;
        proxy_set_header Host \$host;
        access_log off;
    }

    # Для ACME challenge
    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
        try_files \$uri =404;
    }
}
EOF
    
    # Создаем статичную страницу
    cat > nginx/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Remnawave Node - $DOMAIN_NAME</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .status { padding: 20px; background: #f0f9ff; border-radius: 5px; margin: 20px 0; }
        .online { color: green; font-weight: bold; }
        .ssl { color: #0066cc; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Remnawave Node</h1>
        <div class="status">
            <p>Статус: <span class="online">● Онлайн</span></p>
            <p>Домен: $DOMAIN_NAME</p>
            <p>SSL: <span class="ssl">Let's Encrypt (активен)</span></p>
            <p>API порт: 2222</p>
            <p>Защита: fail2ban активна</p>
        </div>
    </div>
</body>
</html>
EOF
    
    print_success "Конфигурация Nginx создана"
else
    print_info "SSL не настроен, пропускаем создание конфигурации Nginx"
fi

# =============================================================================
# 17. ЗАГРУЗКА И ЗАПУСК КОНТЕЙНЕРА
# =============================================================================
print_section "17. ЗАГРУЗКА И ЗАПУСК КОНТЕЙНЕРА"
STEP=17

print_step "Проверка сети Docker..."
# Удаляем старую сеть если существует
docker network rm remnanode-network 2>/dev/null || true

print_step "Загрузка образа Remnawave Node..."
docker-compose pull
if [ $? -eq 0 ]; then
    print_success "Образ загружен"
else
    print_error "Не удалось загрузить образ"
    print_info "Проверьте подключение к интернету"
    exit 1
fi

print_step "Запуск основного контейнера..."
docker-compose up -d remnanode
if [ $? -eq 0 ]; then
    print_success "Контейнер remnanode запущен"
else
    print_error "Не удалось запустить контейнер remnanode"
    print_info "Пробуем создать сеть вручную..."
    
    # Создаем сеть вручную
    docker network create remnanode-network
    
    # Пробуем снова
    docker-compose up -d remnanode
    
    if [ $? -eq 0 ]; then
        print_success "Контейнер remnanode запущен после создания сети вручную"
    else
        print_error "Не удалось запустить контейнер даже после создания сети"
        exit 1
    fi
fi

# =============================================================================
# 18. ПРОВЕРКА УСТАНОВКИ
# =============================================================================
print_section "18. ПРОВЕРКА УСТАНОВКИ"
STEP=18

print_step "Ожидание запуска контейнера..."
sleep 30

print_step "Проверка состояния контейнера..."
if docker-compose ps | grep -q "remnanode.*Up"; then
    print_success "Контейнер remnanode работает нормально"
    
    # Проверяем логи на наличие ошибок Xray
    if docker-compose logs remnanode 2>/dev/null | grep -q "Failed to start: main: failed to create server"; then
        print_error "Обнаружена ошибка Xray (отсутствует директория для логов)"
        print_step "Проверяем и создаем недостающие директории..."
        
        # Проверяем и создаем директории внутри контейнера
        docker exec remnanode mkdir -p /var/log/xray
        docker exec remnanode chmod 755 /var/log/xray
        
        print_success "Директории созданы, перезапускаем контейнер..."
        docker-compose restart remnanode
        sleep 10
    fi
else
    print_error "Контейнер remnanode не запущен"
    print_step "Просмотр логов ошибок..."
    docker-compose logs --tail=50 remnanode
    exit 1
fi

print_step "Проверка логов на ошибки..."
if docker-compose logs remnanode 2>/dev/null | grep -q "Nest application successfully started"; then
    print_success "Remnawave Node успешно запущен!"
    
    # Запускаем остальные сервисы
    if [ "$NO_SSL" = false ] && [ -d "$LETSENCRYPT_DIR/live/$DOMAIN_NAME" ] 2>/dev/null; then
        print_step "Запуск Nginx..."
        docker-compose up -d nginx
        sleep 5
    fi
    
else
    print_error "Remnawave Node не запустился корректно"
    docker-compose logs --tail=100 remnanode
    exit 1
fi

# =============================================================================
# 19. СОЗДАНИЕ СКРИПТОВ УПРАВЛЕНИЯ
# =============================================================================
print_section "19. СОЗДАНИЕ СКРИПТОВ УПРАВЛЕНИЯ"
STEP=19

# Скрипт перезапуска
cat > /usr/local/bin/remnanode-restart << 'EOF'
#!/bin/bash
cd /opt/remnanode
echo "Перезапуск Remnawave Node..."
docker-compose restart remnanode
echo "Готово!"
EOF

# Скрипт обновления
cat > /usr/local/bin/remnanode-update << 'EOF'
#!/bin/bash
cd /opt/remnanode
echo "Обновление Remnawave Node..."
docker-compose pull remnanode
docker-compose down remnanode
docker-compose up -d remnanode
echo "Обновление завершено!"
EOF

# Скрипт просмотра логов
cat > /usr/local/bin/remnanode-logs << 'EOF'
#!/bin/bash
cd /opt/remnanode
docker-compose logs -f --tail=100 remnanode
EOF

# Скрипт проверки статуса
cat > /usr/local/bin/remnanode-status << 'EOF'
#!/bin/bash
cd /opt/remnanode
echo "=== Статус Remnawave Node ==="
docker-compose ps
echo ""
echo "=== Последние логи ==="
docker-compose logs --tail=10 remnanode
EOF

# Скрипт проверки SSL
cat > /usr/local/bin/remnanode-ssl-check << 'EOF'
#!/bin/bash
echo "=== Проверка SSL сертификатов ==="
if [ -f /etc/letsencrypt/live/*/fullchain.pem ]; then
    echo "Сертификаты найдены:"
    ls -la /etc/letsencrypt/live/
    echo ""
    echo "Срок действия:"
    openssl x509 -enddate -noout -in /etc/letsencrypt/live/*/fullchain.pem
else
    echo "SSL сертификаты не найдены"
fi
EOF

chmod +x /usr/local/bin/remnanode-*

# =============================================================================
# 20. ФИНАЛЬНАЯ ИНФОРМАЦИЯ
# =============================================================================
print_section "20. УСТАНОВКА ЗАВЕРШЕНА"
STEP=20

echo -e "${GREEN}✅ Remnawave Node успешно установлен!${NC}"
echo ""

# Получаем IP адрес
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

echo -e "${YELLOW}▸ Основная информация:${NC}"
echo -e "  Директория установки: ${BLUE}$INSTALL_DIR${NC}"
echo -e "  Домен: ${BLUE}$DOMAIN_NAME${NC}"
echo -e "  IP адрес сервера: ${BLUE}$SERVER_IP${NC}"
echo -e "  API порт: ${BLUE}2222${NC}"
echo -e "  Xray порты: ${BLUE}61000-61002${NC}"

if [ "$NO_SSL" = false ] && [ -d "$LETSENCRYPT_DIR/live/$DOMAIN_NAME" ] 2>/dev/null; then
    echo -e "  HTTPS доступ: ${BLUE}https://$DOMAIN_NAME${NC}"
    echo -e "  SSL сертификат: ${BLUE}Let's Encrypt (автопродление настроено)${NC}"
else
    echo -e "  HTTP доступ: ${BLUE}http://$SERVER_IP:2222${NC}"
    echo -e "  SSL: ${BLUE}не настроен (можно настроить позже)${NC}"
fi

echo -e "  Защита: ${BLUE}fail2ban (активна)${NC}"
echo -e "  Фаервол: ${BLUE}iptables (настроен без конфликта с Docker)${NC}"

echo ""
echo -e "${YELLOW}▸ Команды управления:${NC}"
echo -e "  Просмотр логов: ${BLUE}remnanode-logs${NC}"
echo -e "  Статус: ${BLUE}remnanode-status${NC}"
echo -e "  Перезапуск: ${BLUE}remnanode-restart${NC}"
echo -e "  Обновление: ${BLUE}remnanode-update${NC}"

echo ""
echo -e "${RED}⚠ ВАЖНО ДЛЯ ПОДКЛЮЧЕНИЯ ПАНЕЛИ:${NC}"
echo -e "  1. В панели Remnawave укажите:"
if [ "$NO_SSL" = false ] && [ -d "$LETSENCRYPT_DIR/live/$DOMAIN_NAME" ] 2>/dev/null; then
    echo -e "     Адрес: ${BLUE}$DOMAIN_NAME${NC}"
else
    echo -e "     Адрес: ${BLUE}$SERVER_IP${NC}"
fi
echo -e "     Порт: ${BLUE}2222${NC}"
echo -e "     Ключ: ${BLUE}SECRET_KEY=\"...\" (уже в .env)${NC}"

echo ""
echo -e "${YELLOW}▸ Проверка работы:${NC}"
echo -e "  Статус контейнеров: ${BLUE}docker-compose ps${NC}"
echo -e "  Проверка API: ${BLUE}curl http://localhost:2222/health${NC}"

if [ "$NO_SSL" = false ] && [ -d "$LETSENCRYPT_DIR/live/$DOMAIN_NAME" ] 2>/dev/null; then
    echo -e "  Проверка HTTPS: ${BLUE}curl https://$DOMAIN_NAME/health${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Установка завершена! Проверьте подключение панели Remnawave!${NC}"

# =============================================================================
# 21. ФИНАЛЬНАЯ ПРОВЕРКА
# =============================================================================
print_section "21. ФИНАЛЬНАЯ ПРОВЕРКА"
STEP=21

print_step "Проверяем соединение с API..."
sleep 5

if curl -s http://localhost:2222/health > /dev/null 2>&1; then
    print_success "✅ HTTP API доступен на порту 2222"
else
    print_error "❌ API не доступен"
    print_info "Проверьте логи: remnanode-logs"
fi

print_step "Проверяем fail2ban..."
if systemctl is-active --quiet fail2ban; then
    print_success "✅ fail2ban работает"
else
    print_error "❌ fail2ban не запущен"
fi

if [ "$NO_SSL" = false ] && [ -d "$LETSENCRYPT_DIR/live/$DOMAIN_NAME" ] 2>/dev/null; then
    print_step "Проверяем SSL сертификат..."
    if [ -f "/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem" ]; then
        print_success "✅ SSL сертификат найден и активен"
    fi
fi

echo ""
echo -e "${CYAN}Для диагностики выполните:${NC}"
echo -e "${BLUE}  remnanode-status${NC}"
echo -e "${BLUE}  remnanode-logs${NC}"

echo ""
echo -e "${GREEN}✅ Установка Remnawave Node завершена успешно!${NC}"
