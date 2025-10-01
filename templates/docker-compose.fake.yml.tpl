services:
  fake-site:
    image: nginx:alpine
    container_name: vless-fake-site
    restart: {{RESTART_POLICY}}
    volumes:
      - ./fake-site/html:/usr/share/nginx/html:ro
      - ./fake-site/nginx.conf:/etc/nginx/nginx.conf:ro
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - vless-network
    environment:
      - TZ={{TZ}}
    labels:
      - "com.vless.service=fake-site"
      - "com.vless.description=Fallback decoy website"

networks:
  vless-network:
    external: true
    name: {{COMPOSE_PROJECT_NAME}}_vless-network