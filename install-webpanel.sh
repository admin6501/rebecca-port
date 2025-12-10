#!/bin/bash

# ============================================================
#   Install Rebecca Web Panel
#   Author: Khalil Omidian
#   Version: 2.0
# ============================================================

clear
echo "=============================================="
echo "      نصب وب‌پنل Rebecca"
echo "=============================================="

# دریافت پورت و یوزرنیم و پسورد از کاربر
read -p "پورت وب‌پنل را وارد کنید (مثلاً 5000): " PANEL_PORT
read -p "نام کاربری برای ورود به وب‌پنل را وارد کنید: " PANEL_USER
read -sp "رمز عبور برای ورود به وب‌پنل را وارد کنید: " PANEL_PASS
echo ""

# نصب پیش‌نیازها
echo "در حال نصب پیش‌نیازهای Python و کتابخانه‌ها..."
apt update
apt install -y python3 python3-venv python3-pip git curl

# ساخت مسیر نصب وب‌پنل
WEB_DIR="/opt/rebecca-web-panel"
mkdir -p "$WEB_DIR/scripts"
mkdir -p "$WEB_DIR/templates"
mkdir -p "$WEB_DIR/static"

# دانلود اسکریپت اصلی Rebecca Manager
echo "در حال دانلود اسکریپت Rebecca Manager..."
curl -sSL https://raw.githubusercontent.com/admin6501/rebecca-port/refs/heads/main/rebecca-manager2.sh -o "$WEB_DIR/scripts/rebecca-manager2.sh"
chmod +x "$WEB_DIR/scripts/rebecca-manager2.sh"

# ساخت محیط مجازی Python
python3 -m venv "$WEB_DIR/venv"
source "$WEB_DIR/venv/bin/activate"
pip install --upgrade pip
pip install flask flask-socketio eventlet

# ایجاد فایل app.py وب‌پنل با پشتیبانی از ورودی زنده
cat > "$WEB_DIR/app.py" <<EOF
from flask import Flask, render_template, request, session, redirect
from flask_socketio import SocketIO, emit
import subprocess, os, threading

app = Flask(__name__)
app.secret_key = os.urandom(24)
socketio = SocketIO(app)

USERNAME = "$PANEL_USER"
PASSWORD = "$PANEL_PASS"
current_process = None

options = [
"Change image to dev",
"Change image to latest",
"Change Rebecca port",
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

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == "POST":
        user = request.form.get("username")
        pwd = request.form.get("password")
        if user == USERNAME and pwd == PASSWORD:
            session['logged'] = True
            return redirect("/dashboard")
        return "<h3>نام کاربری یا رمز عبور اشتباه است</h3>"
    return render_template("login.html")

@app.route('/dashboard')
def dashboard():
    if not session.get('logged'):
        return redirect("/")
    return render_template("dashboard.html", options=options)

@app.route('/execute', methods=['POST'])
def execute():
    if not session.get('logged'):
        return redirect("/")
    option = request.form.get("option")
    confirm = request.form.get("confirm", "").lower()
    extra_input = request.form.get("extra_input", "")

    if confirm != "yes":
        return render_template("output.html", output="❌ اجرای دستور لغو شد")

    threading.Thread(target=run_script, args=(option, extra_input)).start()
    return render_template("output.html")

def run_script(option, extra_input=""):
    global current_process
    script_path = os.path.join("$WEB_DIR", "scripts", "rebecca-manager2.sh")
    current_process = subprocess.Popen(
        ["bash", script_path],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1
    )

    current_process.stdin.write(f"{option}\n")
    current_process.stdin.flush()
    if extra_input:
        current_process.stdin.write(f"{extra_input}\n")
        current_process.stdin.flush()

    for line in current_process.stdout:
        socketio.emit('output_line', {'data': line})

    current_process = None

@socketio.on("send_input")
def send_input(data):
    global current_process
    if current_process:
        current_process.stdin.write(data["text"] + "\n")
        current_process.stdin.flush()

if __name__ == "__main__":
    socketio.run(app, host="0.0.0.0", port=$PANEL_PORT)
EOF

# فایل‌های قالب HTML
cat > "$WEB_DIR/templates/login.html" <<'EOF'
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head><meta charset="UTF-8"><title>ورود وب‌پنل Rebecca</title></head>
<body>
<h2>ورود به وب‌پنل Rebecca</h2>
<form method="POST">
<label>نام کاربری:</label><input type="text" name="username" required><br>
<label>رمز عبور:</label><input type="password" name="password" required><br>
<button type="submit">ورود</button>
</form>
</body>
</html>
EOF

cat > "$WEB_DIR/templates/dashboard.html" <<'EOF'
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head><meta charset="UTF-8"><title>داشبورد Rebecca</title></head>
<body>
<h2>داشبورد Rebecca</h2>
<form method="POST" action="/execute">
<label>انتخاب گزینه:</label>
<select name="option" id="option_select" onchange="showExtraInput()">
{% for opt in options %}
<option value="{{ loop.index }}">{{ opt }}</option>
{% endfor %}
</select>
<div id="extra_input_div" style="display:none;">
<label>ورودی اضافی (مثلاً پورت یا Yes/No):</label>
<input type="text" name="extra_input">
</div>
<label>تایید اجرا (yes):</label>
<input type="text" name="confirm" required>
<button type="submit">اجرا</button>
</form>
<script>
function showExtraInput(){
  var select = document.getElementById("option_select");
  var div = document.getElementById("extra_input_div");
  if(select.value == "3" || select.value >= "9"){ div.style.display="block"; }
  else{ div.style.display="none"; }
}
</script>
</body>
</html>
EOF

cat > "$WEB_DIR/templates/output.html" <<'EOF'
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head><meta charset="UTF-8"><title>خروجی اجرا</title></head>
<body>
<h2>خروجی اجرا</h2>
<pre id="output"></pre>
<input type="text" id="send_to_script" placeholder="پاسخی که باید به اسکریپت ارسال شود">
<button onclick="sendToScript()">ارسال</button>
<script src="//cdnjs.cloudflare.com/ajax/libs/socket.io/4.6.1/socket.io.min.js"></script>
<script>
var socket = io();
socket.on('output_line', function(msg){
  document.getElementById("output").innerText += msg.data;
});
function sendToScript(){
  var text = document.getElementById("send_to_script").value;
  socket.emit("send_input", {"text": text});
  document.getElementById("send_to_script").value = "";
}
</script>
</body>
</html>
EOF

echo "✅ وب‌پنل نصب شد!"
echo "برای اجرا:"
echo "cd $WEB_DIR && source venv/bin/activate && python app.py"
echo "وب‌پنل روی پورت $PANEL_PORT در دسترس خواهد بود."
