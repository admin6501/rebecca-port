#!/bin/bash

echo "🌐 نصب و راه‌اندازی وب‌پنل Rebecca (نسخه زنده)"

read -p "لطفا پورت وب‌پنل را وارد کنید (مثلا 5000): " PANEL_PORT
read -p "لطفا یوزرنیم ورود را وارد کنید: " PANEL_USER
read -s -p "لطفا پسورد ورود را وارد کنید: " PANEL_PASS
echo ""

echo "🔄 بروزرسانی سیستم و نصب پیش‌نیازها..."
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y python3 python3-pip
pip3 install flask flask-socketio eventlet

echo "📁 ساخت فولدرهای وب‌پنل..."
mkdir -p /opt/rebecca-web-panel/{templates,static,scripts}

echo "📥 دانلود Rebecca Manager Script..."
curl -sSL https://raw.githubusercontent.com/admin6501/rebecca-port/refs/heads/main/rebecca-manager2.sh \
     -o /opt/rebecca-web-panel/scripts/rebecca-manager2.sh
chmod +x /opt/rebecca-web-panel/scripts/rebecca-manager2.sh

echo "💾 ذخیره پیکربندی کاربر..."
cat << EOF > /opt/rebecca-web-panel/config.py
PORT = $PANEL_PORT
USERNAME = "$PANEL_USER"
PASSWORD = "$PANEL_PASS"
EOF
