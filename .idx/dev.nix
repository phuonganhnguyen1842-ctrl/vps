{ pkgs, ... }: {
  channel = "stable-24.11";

  packages = [
    pkgs.docker
    pkgs.cloudflared
    pkgs.socat
    pkgs.netcat
    pkgs.coreutils
    pkgs.apt
    pkgs.systemd
    pkgs.unzip
  ];

  services.docker.enable = true;

  idx.workspace.onStart = {
    novnc = ''
      set -e

      mkdir -p ~/vps
      cd ~/vps || cd /

      echo "▶ Khởi động container..."

      # Tạo container nếu chưa có
      if ! docker ps -a --format '{{.Names}}' | grep -qx 'ubuntu-novnc'; then
        docker pull thuonghai2711/ubuntu-novnc-pulseaudio:22.04

        docker run --name ubuntu-novnc \
          -p 10000:10000 \
          -p 5900:5900 \
          --shm-size 2g \
          --cap-add SYS_ADMIN \
          -d thuonghai2711/ubuntu-novnc-pulseaudio:22.04
      else
        docker start ubuntu-novnc || true
      fi

      echo "⏳ Đang chờ NoVNC khởi động (port 10000)..."

      # Đợi port 10000 mở
      for i in {1..30}; do
        if nc -z 127.0.0.1 10000; then
          echo "✅ NoVNC is ready!"
          break
        fi
        echo "   ➜ Chưa mở, đợi thêm..."
        sleep 2
      done

      # Nếu port không mở → dừng để tránh 502
      if ! nc -z 127.0.0.1 10000; then
        echo "❌ NoVNC KHÔNG mở port 10000 → Cloudflared sẽ bị 502 nên mình dừng lại!"
        exit 1
      fi

      echo "🚀 Khởi chạy Cloudflared..."

      # Chạy Cloudflared và lưu log
      nohup cloudflared tunnel --url http://localhost:10000 \
        > /tmp/cloudflared.log 2>&1 &

      # Chờ log Cloudflared
      sleep 10

      # Lấy URL Cloudflare
      URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)

      if [ -z "$URL" ]; then
        echo "❌ Không tìm thấy URL trong log."
        echo "🔍 Kiểm tra log:  cat /tmp/cloudflared.log"
      else
        echo "========================================="
        echo " 🌍 Cloudflared Tunnel:"
        echo "     $URL"
        echo "========================================="
      fi

      # Giữ session sống
      while true; do sleep 60; done
    '';
  };

  idx.previews = {
    enable = true;
    previews.novnc = {
      manager = "web";
      command = [
        "bash" "-lc"
        "socat TCP-LISTEN:$PORT,fork TCP:127.0.0.1:10000"
      ];
    };
  };
}
