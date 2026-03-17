#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Читаем .env
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
else
    echo "Файл .env не найден. Скопируй .env.example в .env и заполни значения."
    exit 1
fi

DOMAIN="${DOMAIN:-}"
EMAIL="${CERTBOT_EMAIL:-}"

[ -n "$DOMAIN" ] || { echo "Укажи DOMAIN в .env"; exit 1; }
NGINX_CONF="$SCRIPT_DIR/nginx/myshows-proxy.conf"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available/myshows-proxy"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled/myshows-proxy"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

require_root() {
    [ "$EUID" -eq 0 ] || error "Запусти скрипт от root: sudo ./install.sh"
}

install_docker() {
    if command -v docker &>/dev/null; then
        info "Docker уже установлен: $(docker --version)"
        return
    fi
    warn "Docker не найден — устанавливаю..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable --now docker
    info "Docker установлен: $(docker --version)"
}

install_nginx() {
    if command -v nginx &>/dev/null; then
        info "Nginx уже установлен: $(nginx -v 2>&1)"
        return
    fi
    warn "Nginx не найден — устанавливаю..."
    apt-get update -qq
    apt-get install -y -qq nginx
    systemctl enable --now nginx
    info "Nginx установлен: $(nginx -v 2>&1)"
}

install_certbot() {
    if command -v certbot &>/dev/null; then
        info "Certbot уже установлен: $(certbot --version)"
        return
    fi
    warn "Certbot не найден — устанавливаю..."
    apt-get install -y -qq certbot python3-certbot-nginx
    info "Certbot установлен: $(certbot --version)"
}

setup_nginx() {
    info "Настраиваю nginx..."
    cp "$NGINX_CONF" "$NGINX_SITES_AVAILABLE"

    if [ ! -L "$NGINX_SITES_ENABLED" ]; then
        ln -s "$NGINX_SITES_AVAILABLE" "$NGINX_SITES_ENABLED"
        info "Символическая ссылка создана"
    else
        info "Символическая ссылка уже существует"
    fi

    # Убираем default если мешает
    [ -L /etc/nginx/sites-enabled/default ] && rm /etc/nginx/sites-enabled/default && warn "Удалён default сайт nginx"

    nginx -t || error "Ошибка в конфиге nginx"
    systemctl reload nginx
    info "Nginx перезагружен"
}

setup_ssl() {
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        info "SSL-сертификат уже есть для $DOMAIN"
        return
    fi
    warn "Получаю SSL-сертификат для $DOMAIN..."
    if [ -n "$EMAIL" ]; then
        certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL"
    else
        certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email
    fi
    info "SSL-сертификат получен"
}

start_service() {
    info "Запускаю docker compose..."
    cd "$(dirname "$0")"
    docker compose up -d --build
    info "Сервис запущен"
}

# --- main ---
require_root

echo ""
echo "=== MyShows Proxy — установка ==="
echo "Домен: $DOMAIN"
echo ""

install_docker
install_nginx
install_certbot
setup_nginx
setup_ssl
start_service

echo ""
info "Готово! Прокси доступен на https://$DOMAIN"
