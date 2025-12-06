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
    pkgs.netcat
  ];

  services.docker.enable = true;

  idx.workspace.onStart = {
    novnc = ''
      set -e

      # Ensure working directory exists
      mkdir -p ~/vps
      cd ~/vps || cd /

      # One-time cleanup
      if [ ! -f /home/user/.cleanup_done ]; then
        rm -rf /home/user/.gradle/* /home/user/.emu/*
        find /home/user -mindepth 1 -maxdepth 1 ! -name 'idx-ubuntu22-gui' ! -name '.*' -exec rm -rf {} +
        touch /home/user/.cleanup_done
      fi

      # Pull and start Docker container
      if ! docker ps -a --format '{{.Names}}' | grep -qx 'ubuntu-novnc'; then
        docker pull thuonghai2711/ubuntu-novnc-pulseaudio:22.04
        docker run --name ubuntu-novnc \
          -p 10000:10000 \
          -p 5900:5900 \
          --shm-size 2g \
          --cap-add=SYS_ADMIN \
          -d thuonghai2711/ubuntu-novnc-pulseaudio:22.04
      else
        docker start ubuntu-novnc || true
      fi

      # Wait for Novnc WebSocket
      while ! nc -z localhost 10000; do sleep 1; done

      # Install Chrome + XFCE + codecs
      docker exec -it ubuntu-novnc bash -lc "
        sudo apt update &&
        sudo apt remove -y firefox || true &&
        sudo apt install -y wget xfce4 xfce4-terminal x11-apps x11-utils \
          fonts-liberation \
          ffmpeg libvpx7 libavcodec-extra \
          gstreamer1.0-libav gstreamer1.0-plugins-good \
          gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly &&
        sudo wget -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb &&
        sudo apt install -y /tmp/chrome.deb &&
        sudo rm -f /tmp/chrome.deb
      "

      # Run Chrome in container with proper flags
      docker exec -d ubuntu-novnc bash -lc "
        google-chrome --no-sandbox --disable-gpu --disable-software-rasterizer --disable-dev-shm-usage &
      "

      # Start Cloudflared tunnel
      nohup cloudflared tunnel --no-autoupdate --url http://localhost:10000 \
        > /tmp/cloudflared.log 2>&1 &

      sleep 10

      # Extract Cloudflared URL
      URL=""
      for i in {1..15}; do
        URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
        if [ -n "$URL" ]; then break; fi
        sleep 1
      done

      # Get container IP
      CONTAINER_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ubuntu-novnc)

      # Print info
      echo "========================================="
      if [ -n "$URL" ]; then
        echo " 🌍 Cloudflared tunnel ready:"
        echo "     $URL"
      else
        echo "❌ Cloudflared tunnel failed, check /tmp/cloudflared.log"
      fi

      echo ""
      echo " 🔧 Direct Control IP (for controller software):"
      echo "     $CONTAINER_IP : 10000"
      echo "========================================="

      # Keep script alive
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
          "socat TCP-LISTEN:$PORT,fork,reuseaddr TCP:127.0.0.1:10000"
        ];
      };
    };
  };
}
