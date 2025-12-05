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
    pkgs.docker
    pkgs.systemd
    pkgs.unzip
  ];

  services.docker.enable = true;

  idx.workspace.onStart = {
    novnc = ''
      set -e

      # One-time cleanup
      if [ ! -f /home/user/.cleanup_done ]; then
        rm -rf /home/user/.gradle/* /home/user/.emu/*
        find /home/user -mindepth 1 -maxdepth 1 ! -name 'idx-ubuntu22-gui' ! -name '.*' -exec rm -rf {} +
        touch /home/user/.cleanup_done
      fi

      # Create the container if missing; otherwise start it
      if ! docker ps -a --format '{{.Names}}' | grep -qx 'ubuntu-novnc'; then
        docker run --name ubuntu-novnc \
          --shm-size 1g -d \
          --cap-add=SYS_ADMIN \
          -p 8080:10000 \
          --network host \ # DÒNG ĐÃ THÊM: Sử dụng mạng của host để đảm bảo truy cập internet
          -e VNC_PASSWD=12345678 \
          -e PORT=10000 \
          -e AUDIO_PORT=1699 \
          -e WEBSOCKIFY_PORT=6900 \
          -e VNC_PORT=5900 \
          -e SCREEN_WIDTH=1024 \
          -e SCREEN_HEIGHT=768 \
          -e SCREEN_DEPTH=24 \
          thuonghai2711/ubuntu-novnc-pulseaudio:22.04
      else
        docker start ubuntu-novnc || true
      fi

      # Install Chrome inside the container (sudo only here)
      # Lệnh này bây giờ sẽ hoạt động nhờ có mạng
      docker exec -it ubuntu-novnc bash -lc "
        sudo apt update &&
        sudo apt remove -y firefox || true &&
        sudo apt install -y wget &&
        sudo wget -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb &&
        sudo apt install -y /tmp/chrome.deb &&
        sudo rm -f /tmp/chrome.deb
      "

      # Run cloudflared in background, capture logs
      nohup cloudflared tunnel --no-autoupdate --url http://localhost:8080 \
        > /tmp/cloudflared.log 2>&1 &

      # Give it 10s to start
      sleep 10

      # Extract tunnel URL from logs
      if grep -q "trycloudflare.com" /tmp/cloudflared.log; then
        URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
        echo "========================================="
        echo " 🌍 Your Cloudflared tunnel is ready:"
        echo "     $URL"
        echo "========================================="
      else
        echo "❌ Cloudflared tunnel failed, check /tmp/cloudflared.log"
      fi

      elapsed=0; while true; do echo "Time elapsed: $elapsed min"; ((elapsed++)); sleep 60; done

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