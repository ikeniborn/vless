services:
  xray-server:
    image: teddysun/xray:latest
    container_name: xray-server
    restart: {{RESTART_POLICY}}
    network_mode: host
    volumes:
      - ./config:/etc/xray:ro
      - ./logs:/var/log/xray
      - ./data:/data:ro
    environment:
      - TZ={{TZ}}
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "443"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s