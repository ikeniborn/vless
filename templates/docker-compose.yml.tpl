services:
  xray-server:
    image: teddysun/xray:latest
    container_name: xray-server
    restart: {{RESTART_POLICY}}
    ports:
      - "{{SERVER_PORT}}:443"
    volumes:
      - ./config:/etc/xray:ro
      - ./logs:/var/log/xray
      - ./data:/data:ro
    environment:
      - TZ={{TZ}}
    networks:
      - vless-network
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "443"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  vless-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/16