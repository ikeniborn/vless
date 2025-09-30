services:
  xray-server:
    image: teddysun/xray:24.11.30
    container_name: xray-server
    restart: {{RESTART_POLICY}}
    ports:
      - "{{SERVER_PORT}}:443"
    networks:
      - vless-network
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

networks:
  vless-network:
    driver: bridge
    ipam:
      config:
        - subnet: {{DOCKER_SUBNET}}
          gateway: {{DOCKER_GATEWAY}}