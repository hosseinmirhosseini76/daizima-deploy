# Include inside the daizima.com (apex) HTTPS server block — BEFORE `location /`.
# Serves Electron auto-update artifacts for Daizima Accounting.
#
# Disk layout on server:
#   /var/www/daizima-desktop-updates/accounting/latest.yml
#   /var/www/daizima-desktop-updates/accounting/Daizima-Accounting-Setup-*.exe
#   /var/www/daizima-desktop-updates/accounting/Daizima-Accounting-Setup-*.exe.blockmap
#
# Public URL feed (electron-updater generic):
#   https://daizima.com/desktop-updates/accounting/
#
# Cloudflare: add Cache Rule Bypass / Respect origin for
#   daizima.com/desktop-updates/*

location ^~ /desktop-updates/ {
    alias /var/www/daizima-desktop-updates/;
    autoindex off;
    sendfile on;
    # Versioned .exe names are immutable; latest.yml must not be cached aggressively.
    add_header Cache-Control "public, max-age=60" always;
    add_header X-Content-Type-Options "nosniff" always;
    types {
        application/octet-stream exe;
        text/yaml yml yaml;
        application/octet-stream blockmap;
    }
    default_type application/octet-stream;
}

location = /desktop-updates/accounting/latest.yml {
    alias /var/www/daizima-desktop-updates/accounting/latest.yml;
    default_type text/yaml;
    add_header Cache-Control "no-cache, no-store, must-revalidate" always;
}
