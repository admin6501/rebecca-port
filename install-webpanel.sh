#!/bin/bash

# ============================================================
#  Install & Run Rebecca Web Panel
#  Author: Khalil Omidian
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear
echo -e "${CYAN}=============================================================="
echo "        نصب و راه‌اندازی وب‌پنل Rebecca"
echo -e "==============================================================${NC}"

# ============================
#  دریافت ورودی کاربر
# ============================
read -p "لطفا پورت وب‌پنل را وارد کنید (مثلا 5000): " PANEL_PORT
read -p "لطفا نام کاربری ورود را وارد کنید: " PANEL_USER
read -s -p "لطفا رمز عبور ورود را وارد کنید: " PANEL_PASS
echo ""
echo -e "${BLUE}🔄 بروزرسانی سیستم و نصب پیش‌نیازها...${NC}"
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y python3 python3-pip curl

pip3 install flask flask-socketio eventlet

# ============================
#  ساخت فولدرهای وب‌پنل
# ============================
echo -e "${BLUE}📁 ساخت فولدرهای وب‌پنل...${NC}"
mkdir -p /opt/rebecca-web-panel/{templates,static,scripts}

# ============================
#  دانلود اسکریپت Rebecca Manager
# ============================
echo -e "${BLUE}📥 دانلود Rebecca Manager Script...${NC}"
curl -sSL https://raw.githubusercontent.com/admin6501/rebecca-port/refs/heads/main/rebecca-manager2.sh \
     -o /opt/rebecca-web-panel/scripts/rebecca-manager2.sh
chmod +x /opt/rebecca-web-panel/scripts/rebecca-manager2.sh

# ============================
#  ذخیره پیکربندی
# ============================
echo -e "${BLUE}💾 ذخیره پیکربندی کاربر...${NC}"
cat << EOF > /opt/rebecca-web-panel/config.py
PORT = $PANEL_PORT
USERNAME = "$PANEL_USER"
PASSWORD = "$PANEL_PASS"
EOF

# ============================
#  ایجاد وب‌پنل Flask + SocketIO
# ============================

echo -e "${BLUE}⚙️ ساخت فایل app.py و قالب‌های وب‌پنل...${NC}"

cat << 'EOF' > /opt/rebecca-web-panel/app.py
from flask import Flask, render_template, request, redirect, session
from flask_socketio import SocketIO, emit
import subprocess
import config

app = Flask(__name__)
app.secret_key = 'khalil-secret'
socketio = SocketIO(app)

@app.route("/", methods=["GET","POST"])
def login():
    if request.method=="POST":
        if request.form.get("username")==config.USERNAME and request.form.get("password")==config.PASSWORD:
            session['logged']=True
            return redirect("/dashboard")
        else:
            return render_template("login.html", error="نام کاربری یا رمز اشتباه است")
    return render_template("login.html")

@app.route("/dashboard")
def dashboard():
    if not session.get('logged'):
        return redirect("/")
    options = [
        "تغییر ایمیج به dev",
        "تغییر ایمیج به latest",
        "تغییر پورت Rebecca",
        "Rebecca up",
        "Rebecca down",
        "Rebecca restart",
        "Rebecca status",
        "Rebecca logs",
        "Rebecca install (SQLite)",
        "Rebecca install (MySQL)",
        "Rebecca install (MariaDB)",
        "Rebecca service-install",
        "Rebecca service-update",
        "Rebecca service-status",
        "Rebecca service-logs",
        "Rebecca service-uninstall",
        "Rebecca backup",
        "Rebecca backup-service",
        "Rebecca update",
        "Install Rebecca Node",
        "Rebecca core-update",
        "Rebecca uninstall"
    ]
    return render_template("dashboard.html", options=options)

@app.route("/execute", methods=["POST"])
def execute():
    if not session.get('logged'):
        return redirect("/")
    option = request.form.get("option")
    confirm = request.form.get("confirm")
    if confirm != "yes":
        return render_template("output.html", output="❌ اجرای دستور لغو شد")
    socketio.start_background_task(target=run_command_live, option=option)
    return render_template("output.html")

def run_command_live(option):
    script = "/opt/rebecca-web-panel/scripts/rebecca-manager2.sh"
    process = subprocess.Popen(["bash", script], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    process.stdin.write(f"{option}\n")
    process.stdin.flush()
    for line in process.stdout:
        socketio.emit('output_line', {'data': line})
    process.wait()

if __name__=="__main__":
    socketio.run(app, host="0.0.0.0", port=config.PORT)
EOF

# ============================
#  قالب‌ها
# ============================
cat << 'EOF' > /opt/rebecca-web-panel/templates/login.html
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
<meta charset="UTF-8">
<title>ورود وب‌پنل Rebecca</title>
<link rel="stylesheet" href="/static/style.css">
</head>
<body>
<div class="box">
<h2>ورود به وب‌پنل Rebecca</h2>
{% if error %}<p class="error">{{ error }}</p>{% endif %}
<form method="POST">
<label>نام کاربری</label>
<input type="text" name="username" required>
<label>رمز عبور</label>
<input type="password" name="password" required>
<button type="submit">ورود</button>
</form>
</div>
</body>
</html>
EOF

cat << 'EOF' > /opt/rebecca-web-panel/templates/dashboard.html
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
<meta charset="UTF-8">
<title>داشبورد وب‌پنل Rebecca</title>
<link rel="stylesheet" href="/static/style.css">
</head>
<body>
<div class="box">
<h2>داشبورد Rebecca</h2>
<form method="POST" action="/execute">
<label>انتخاب گزینه:</label>
<select name="option">
{% for opt in options %}
<option value="{{ loop.index }}">{{ opt }}</option>
{% endfor %}
</select>
<label>تایید اجرا (yes/خیر):</label>
<input type="text" name="confirm" required>
<button type="submit">اجرا</button>
</form>
</div>
</body>
</html>
EOF

cat << 'EOF' > /opt/rebecca-web-panel/templates/output.html
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
<meta charset="UTF-8">
<title>خروجی دستور</title>
<script src="https://cdnjs.cloudflare.com/ajax/libs/socket.io/4.7.2/socket.io.min.js"></script>
<link rel="stylesheet" href="/static/style.css">
</head>
<body>
<div class="box">
<h2>خروجی زنده دستور</h2>
<pre id="output"></pre>
<a href="/dashboard">بازگشت</a>
</div>
<script>
var socket = io();
var output = document.getElementById("output");
socket.on('output_line', function(msg){
    output.innerText += msg.data;
    window.scrollTo(0, document.body.scrollHeight);
});
</script>
</body>
</html>
EOF

# ============================
#  CSS
# ============================
cat << 'EOF' > /opt/rebecca-web-panel/static/style.css
body { background:#f5f5f5; font-family:tahoma; }
.box { max-width:700px; margin:50px auto; padding:20px; background:white; border-radius:12px; box-shadow:0 0 10px #ccc; }
h2 { text-align:center; }
label { display:block; margin-top:10px; }
input, select { width:100%; padding:8px; margin-top:5px; }
button { padding:10px; width:100%; margin-top:15px; background:#007bff;color:white;border:none;border-radius:6px; cursor:pointer;}
pre { background:#eee; padding:10px; overflow:auto; border-radius:8px;}
.error { color:red; text-align:center;}
a { display:block; text-align:center; margin-top:15px; }
EOF

# ============================
#  اجرای وب‌پنل
# ============================
echo -e "${GREEN}✅ نصب کامل شد. وب‌پنل در حال اجراست...${NC}"
python3 /opt/rebecca-web-panel/app.py
