{ pkgs, ... }: {
  channel = "stable-24.11";

  packages = [
    pkgs.docker
    pkgs.cloudflared
    pkgs.socat
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.sudo
    pkgs.apt
    pkgs.systemd
    pkgs.unzip
  ];

  services.docker.enable = true;

  idx.workspace.onStart = {
    novnc = ''
      set -e

      echo "🧹 Cleanup once..."
      if [ ! -f /home/user/.cleanup_done ]; then
        rm -rf /home/user/.gradle/* /home/user/.emu/*
        find /home/user -mindepth 1 -maxdepth 1 ! -name 'idx-ubuntu22-gui' ! -name '.*' -exec rm -rf {} +
        touch /home/user/.cleanup_done
      fi

      echo "🐳 Checking container..."
      if ! docker ps -a --format '{{.Names}}' | grep -qx 'ubuntu-novnc'; then
        echo "➡️ Creating new container..."
        docker run --name ubuntu-novnc \
          --shm-size 2g \
          --memory 3g \
          --cpus 2 \
          --cap-add=SYS_ADMIN \
          -d \
          -p 8080:10000 \
          -e VNC_PASSWD=12345678 \
          -e PORT=10000 \
          -e AUDIO_PORT=1699 \
          -e WEBSOCKIFY_PORT=6900 \
          -e VNC_PORT=5900 \
          -e SCREEN_WIDTH=1280 \
          -e SCREEN_HEIGHT=720 \
          -e SCREEN_DEPTH=24 \
          thuonghai2711/ubuntu-novnc-pulseaudio:22.04
      else
        echo "➡️ Starting existing container..."
        docker start ubuntu-novnc || true
      fi

      echo "🌐 Installing Chrome..."
      docker exec -it ubuntu-novnc bash -lc "
        sudo apt update &&
        sudo apt remove -y firefox || true &&
        sudo apt install -y wget &&
        sudo wget -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb &&
        sudo apt install -y /tmp/chrome.deb &&
        sudo rm -f /tmp/chrome.deb
      "

      echo "🖥️ Adding Win10 menu interface..."
      docker exec -i ubuntu-novnc bash -lc "cat > /usr/share/novnc/index.html << 'EOF'
<!doctype html>
<html lang='en'>
<head>
<meta charset='utf-8'>
<title>Cloud Desktop</title>
<style>
body{
  font-family:Segoe UI,Arial;
  background:#0f1724;
  color:white;
  display:flex;
  justify-content:center;
  align-items:center;
  height:100vh;
  margin:0;
}
.box{
  background:#111827;
  padding:30px;
  border-radius:14px;
  width:400px;
  text-align:center;
  box-shadow:0 0 40px #0008;
}
h1{font-size:24px;margin-bottom:10px;}
p{color:#cbd5e1;margin-bottom:20px;}
button{
  padding:12px 18px;
  border:0;
  border-radius:8px;
  background:#2563eb;
  color:white;
  font-size:15px;
  font-weight:600;
  cursor:pointer;
  width:100%;
  margin-top:10px;
}
.loading{
  display:none;
  margin-top:20px;
  color:#94a3b8;
}
</style>
</head>
<body>
<div class='box'>
  <h1>Cloud Desktop</h1>
  <p>Chọn giao diện để bắt đầu</p>
  <button onclick="go()">Vào Windows 10</button>
  <button onclick="go()">Vào Ubuntu</button>
  <div class='loading' id='load'>Đang tải giao diện...</div>
</div>

<script>
function go(){
  document.getElementById('load').style.display='block';
  setTimeout(function(){
    window.location='/vnc.html';
  }, 2500);
}
</script>
</body>
</html>
EOF"
      "

      docker exec ubuntu-novnc chmod 644 /usr/share/novnc/index.html || true

      echo "☁️ Starting cloudflared..."
      nohup cloudflared tunnel --no-autoupdate --url http://localhost:8080 \
        > /tmp/cloudflared.log 2>&1 &

      echo "⏳ Waiting for tunnel..."
      sleep 10

      if grep -q "trycloudflare.com" /tmp/cloudflared.log; then
        URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
        echo "========================================="
        echo "🌍 Cloud Desktop Ready!"
        echo "$URL"
        echo "🔑 Password (VNC): 12345678"
        echo "========================================="
      else
        echo "❌ Tunnel failed — check /tmp/cloudflared.log"
      fi

      elapsed=0
      while true; do
        echo "⏱️ Online: $elapsed min"
        ((elapsed++))
        sleep 60
      done
    '';
  };

  idx.previews = {
    enable = true;
    previews = {
      novnc = {
        manager = "web";
        command = [
          "bash" "-lc"
          "socat TCP-LISTEN:$PORT,fork,reuseaddr TCP:127.0.0.1:8080"
        ];
      };
    };
  };
}
