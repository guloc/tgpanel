#!/bin/bash

# Установка цветного вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Установка TG Panel${NC}"
echo -e "${GREEN}============================================${NC}"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Запустите скрипт от имени root:${NC}"
    echo -e "${YELLOW}curl -sSL https://raw.githubusercontent.com/guloc/tgpanel/master/install_tgpanel.sh | sudo bash${NC}"
    exit 1
fi

# Функция для проверки успешности операции
check() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[✓] $1${NC}"
        return 0
    else
        echo -e "${RED}[✗] $1${NC}"
        return 1
    fi
}

# Функция для проверки наличия процесса
check_process() {
    if pgrep -f "$1" > /dev/null; then
        return 0
    else
        return 1
    fi
}

echo -e "\n${YELLOW}[1/7] Обновление системы...${NC}"
apt update && apt upgrade -y
check "Обновление системы"

echo -e "\n${YELLOW}[2/7] Установка необходимых пакетов...${NC}"
apt install -y wget curl unzip git ffmpeg cron ufw python3 python3-pip expect
check "Установка пакетов"

echo -e "\n${YELLOW}[3/7] Настройка файрвола...${NC}"
# Открываем необходимые порты
ufw allow ssh
ufw allow 80
ufw allow 443
ufw allow 20
ufw allow 21
ufw allow 888
ufw allow 38532
ufw allow 10514
echo "y" | ufw enable
check "Настройка файрвола"

echo -e "\n${YELLOW}[4/7] Удаление старой установки...${NC}"
if systemctl is-active --quiet bt; then
    systemctl stop bt
fi
killall -9 bt-panel >/dev/null 2>&1
killall -9 bt-task >/dev/null 2>&1
rm -rf /www/server/panel
rm -rf /www/server/nginx
rm -rf /www/server/nodejs
rm -f /etc/init.d/bt
systemctl daemon-reload
check "Удаление старой установки"

echo -e "\n${YELLOW}[5/7] Установка aaPanel...${NC}"
# Скачиваем установщик
if ! wget -O aapanel.sh https://www.aapanel.com/script/install-ubuntu_6.0_en.sh; then
    echo -e "${RED}Ошибка загрузки установщика aaPanel${NC}"
    exit 1
fi

# Создаем expect скрипт для автоматического ответа
cat > install_aapanel.exp << 'EOF'
#!/usr/bin/expect -f
set timeout -1

spawn bash aapanel.sh aapanel

# Отвечаем "y" на все вопросы
expect {
    "Do you want to install aaPanel" { send "y\r"; exp_continue }
    "Do you need to install offline" { send "n\r"; exp_continue }
    "Please enter your email" { send "admin@localhost\r"; exp_continue }
    eof
}
EOF

# Делаем expect скрипт исполняемым
chmod +x install_aapanel.exp

# Запускаем установку через expect
./install_aapanel.exp

# Проверяем успешность установки
if [ ! -f "/www/server/panel/data/port.pl" ]; then
    echo -e "${RED}Ошибка установки aaPanel. Проверьте логи установки.${NC}"
    exit 1
fi

check "Установка aaPanel"

echo -e "\n${YELLOW}[6/7] Ожидание запуска aaPanel...${NC}"
# Ждем запуска процессов панели
counter=0
while ! check_process "bt-panel" && [ $counter -lt 30 ]; do
    sleep 10
    counter=$((counter + 1))
    echo -e "${YELLOW}Ожидание запуска панели... ($counter/30)${NC}"
done

if ! check_process "bt-panel"; then
    echo -e "${RED}Ошибка: панель не запустилась после установки${NC}"
    exit 1
fi

check "Запуск панели"

echo -e "\n${YELLOW}[7/7] Настройка прав доступа...${NC}"
mkdir -p /www/wwwroot
chmod -R 755 /www/wwwroot/
mkdir -p /www/wwwroot/*/app/cache
mkdir -p /www/wwwroot/*/app/logs
mkdir -p /www/wwwroot/*/session.madeline
mkdir -p /www/wwwroot/*/assets/upload
chmod -R 777 /www/wwwroot/*/app/cache
chmod -R 777 /www/wwwroot/*/app/logs
chmod -R 777 /www/wwwroot/*/session.madeline
chmod -R 777 /www/wwwroot/*/assets/upload
check "Настройка прав"

# Получение данных для входа
PANEL_INFO=$(cat /www/server/panel/default.pl 2>/dev/null)
PANEL_PORT=$(cat /www/server/panel/data/port.pl 2>/dev/null)
PANEL_PATH=$(cat /www/server/panel/data/admin_path.pl 2>/dev/null)
EXTERNAL_IP=$(curl -s https://api.ipify.org)

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Установка завершена!${NC}"
echo -e "\n${YELLOW}Данные для входа в aaPanel:${NC}"
echo "URL: https://$EXTERNAL_IP:$PANEL_PORT/$PANEL_PATH"
echo "Проверьте файл /www/server/panel/default.pl для получения пароля"

echo -e "\n${YELLOW}Следующие шаги:${NC}"
echo "1. Войдите в панель управления по указанному выше URL"
echo "2. Установите PHP 8.2 через панель управления"
echo "3. Установите необходимые расширения PHP:"
echo "   - curl"
echo "   - gd"
echo "   - mbstring"
echo "   - mysql"
echo "   - xml"
echo "   - zip"
echo "4. Создайте новый веб-сайт для tgpanel"
echo "5. Настройте SSL сертификат"

echo -e "\n${YELLOW}Важно:${NC}"
echo "- Смените пароль администратора"
echo "- Настройте регулярные бэкапы"
echo "- Проверьте работу Cron заданий"
echo -e "${GREEN}============================================${NC}"

# Сохранение данных установки
echo "Installation Date: $(date)" > /root/tgpanel_info.txt
echo "Panel URL: https://$EXTERNAL_IP:$PANEL_PORT/$PANEL_PATH" >> /root/tgpanel_info.txt
echo "Panel Port: $PANEL_PORT" >> /root/tgpanel_info.txt
echo "Admin Path: $PANEL_PATH" >> /root/tgpanel_info.txt
echo "Default Password: $PANEL_INFO" >> /root/tgpanel_info.txt

echo -e "\n${YELLOW}Данные сохранены в файл: /root/tgpanel_info.txt${NC}"
echo -e "${GREEN}Установка успешно завершена!${NC}"
