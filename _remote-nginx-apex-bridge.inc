# Include inside the EXISTING daizima.com HTTPS server (the one that still
# proxies / to 127.0.0.1:3000). Do not replace that vhost.
# Copy this file to /etc/nginx/snippets/daizima-apex-bridge.inc and add:
#
#   include /etc/nginx/snippets/daizima-apex-bridge.inc;
#
# Put the include inside the listen 443 server, before `location /`.
# Prefix ^~ still wins even if `location /` is defined first.
#
# SSO: /auth/* + /_sf/ → new storefront on :3021
# Legacy bookmarks: /panel → admin, /user-panel → user

location ^~ /_sf/ {
    proxy_pass http://127.0.0.1:3021;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $proxy_x_forwarded_proto;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_buffering off;
}

location = /auth {
    return 301 /auth/continue;
}

location ^~ /auth/ {
    proxy_pass http://127.0.0.1:3021;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $proxy_x_forwarded_proto;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_buffering off;
}

location ^~ /panel {
    return 301 https://admin.daizima.com$request_uri;
}

location = /user-panel {
    return 301 https://user.daizima.com/;
}

location ^~ /user-panel/ {
    rewrite ^/user-panel/(.*)$ https://user.daizima.com/$1 permanent;
}
