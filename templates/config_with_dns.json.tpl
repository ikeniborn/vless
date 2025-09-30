{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "dns": {
    "servers": [
      {
        "address": "{{DNS_PRIMARY}}",
        "port": 53,
        "domains": [
          "geosite:geolocation-!cn"
        ],
        "expectIPs": [
          "geoip:!cn"
        ]
      }{{DNS_SECONDARY_SERVER_OBJECT}},
      {
        "address": "114.114.114.114",
        "port": 53,
        "domains": [
          "geosite:cn"
        ],
        "expectIPs": [
          "geoip:cn"
        ],
        "skipFallback": true
      }
    ],
    "hosts": {
      "domain:googleapis.cn": "googleapis.com",
      "domain:gstatic.cn": "gstatic.com"
    },
    "queryStrategy": "UseIPv4",
    "disableCache": false,
    "disableFallback": true,
    "tag": "dns_inbound"
  },
  "api": {
    "tag": "api",
    "services": [
      "StatsService"
    ]
  },
  "stats": {},
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "tag": "vless-in",
      "settings": {
        "clients": [
          {
            "id": "{{ADMIN_UUID}}",
            "flow": "xtls-rprx-vision",
            "level": 0
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": "vless-fake-site:80",
            "xver": 0
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "{{REALITY_DEST}}",
          "serverNames": [
            "{{REALITY_SERVER_NAME}}",
            "www.microsoft.com",
            "www.apple.com",
            "github.com",
            "www.cloudflare.com",
            "stackoverflow.com",
            "www.wikipedia.org"
          ],
          "privateKey": "{{PRIVATE_KEY}}",
          "minClientVer": "1.8.0",
          "maxClientVer": "",
          "maxTimeDiff": 90,
          "shortIds": [
            "",
            "{{ADMIN_SHORT_ID}}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    },
    {
      "port": 62789,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct",
      "settings": {
        "domainStrategy": "UseIP"
      }
    },
    {
      "protocol": "blackhole",
      "tag": "block",
      "settings": {
        "response": {
          "type": "http"
        }
      }
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "comment": "API routing - Stats API для мониторинга",
        "inboundTag": [
          "api"
        ],
        "outboundTag": "api"
      },
      {
        "type": "field",
        "comment": "Блокировка BitTorrent протокола",
        "protocol": [
          "bittorrent"
        ],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "comment": "Блокировка опасных портов (SMTP, POP3, RPC, SMB)",
        "port": "25,110,135,139,445,465,587",
        "outboundTag": "block"
      },
      {
        "type": "field",
        "comment": "Блокировка рекламы и трекеров",
        "domain": [
          "geosite:category-ads-all"
        ],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "comment": "Default routing - весь остальной трафик разрешён",
        "network": "tcp,udp",
        "outboundTag": "direct"
      }
    ]
  }
}