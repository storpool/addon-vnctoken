# Using websocketproxy for noVNC

## Installation

Checkout the websockify for noVNC

```bash
git clone --depth=1 https://github.com/novnc/websockify /var/lib/one/websockify-novnc
chown oneadmin.oneadmin /var/lib/one/websockify-novnc
```

Copy the content of the _etc_ folder to the system:

```bash
cp -va etc/* /etc/
systemctl daemon-reload
```

## Configuration

### websockify-novnc
Edit `/etc/sysconfig/websockify-novnc` with paths to the ssl cert and key files.

### Nginx

```
# Websocketproxy (noVNC console)
upstream websocketproxy-novnc {
  server 127.0.0.1:29877;
}
```

```
server {
    ...
    location /websockify-novnc {
        proxy_http_version 1.1;
        proxy_pass http://websocketproxy-novnc;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        # VNC connection timeout
        proxy_read_timeout 61s;
        # Disable cache
        proxy_buffering off;
    }
    ...
}
```

## Usage

Restart the opennebula service to activate the websockify-novnc service.

Check the service log in case of issues `/var/log/one/websockify-novnc.log`
