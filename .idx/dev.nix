{ pkgs, ... }: {
  channel = "stable-24.11";

  packages = [
    pkgs.docker
    pkgs.cloudflared
    pkgs.socat
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.sudo
    pkgs.unzip
  ];

  services.docker.enable = true;

  idx.workspace.onStart = {
    desktop = ''
      set -e

      echo "[1/6] 🔹 Cleanup lần đầu..."
      if [ ! -f /home/user/.cleanup_done ]; then
        rm -rf /home/user/.gradle/* /home/user/.emu/*
        find /home/user -mindepth 1 -maxdepth 1 \
          ! -name 'idx-ubuntu22-gui' \
          ! -name '.*' \
          -exec rm -rf {} +
        touch /home/user/.cleanup_done
      fi

      echo "[2/6] 🔹 Khởi động Docker container GUI..."
      if ! docker ps -a --format '{{.Names}}' | grep -qx 'ubuntu-novnc'; then
        docker run --name ubuntu-novnc \
          --shm-size 1g -d \
          --cap-add=SYS_ADMIN \
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
        docker start ubuntu-novnc || true
      fi

      echo "[3/6] 🔹 Cài Chrome bên trong container..."
      docker exec -it ubuntu-novnc bash -lc "
        sudo apt update &&
        sudo apt remove -y firefox || true &&
        sudo apt install -y wget &&
        sudo wget -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb &&
        sudo apt install -y /tmp/chrome.deb &&
        sudo rm -f /tmp/chrome.deb
      "

      echo "[4/6] 🔹 Mở Cloudflare Tunnel..."
      nohup cloudflared tunnel --no-autoupdate --url http://localhost:8080 \
        > /tmp/cloudflared.log 2>&1 &

      sleep 10

      echo "[5/6] 🔹 Lấy URL tunnel..."
      if grep -q "trycloudflare.com" /tmp/cloudflared.log; then
        URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
        echo "========================================="
        echo " 🌍 Cloud Desktop của bạn đã sẵn sàng!"
        echo " 🔗 Link: $URL"
        echo " 🔑 Mật khẩu VNC: 12345678"
        echo "========================================="
      else
        echo "❌ Không tìm thấy URL cloudflared, xem file: /tmp/cloudflared.log"
      fi

      echo "[6/6] 🔹 Đang chạy… Không tắt tab!"
      elapsed=0; while true; do echo "Đã chạy: $elapsed phút"; ((elapsed++)); sleep 60; done
    '';
  };

  idx.previews = {
    enable = true;
    previews = {
      desktop = {
        manager = "web";
        command = [
          "bash" "-lc"
          "socat TCP-LISTEN:$PORT,fork,reuseaddr TCP:127.0.0.1:8080"
        ];
      };
    };
  };
}
