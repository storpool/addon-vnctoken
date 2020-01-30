# addon-vnctoken
OpenNebula addon to provide VNC tokens for websocketproxy via dedicated XML-RPC api endpoint

## Introduction

For VNC console access OpenNebula uses a websocketproxy that is managed by opennebula-sunstone service. This addon provide a XML-RPC service that could create websocketproxy tokens and provide the details needed to create a VNC session without the need of authentication in sunstone.


The following example is created using CentOS 7 OS and nginx configured as a reverse proxy with enabled Let's Encrypt certificate. For other OS or reverse proxy programs please follow their configuration guides.

## Installation

```bash
sudo cp -a usr/lib/one/vnctoken /usr/lib/one/

sudo cp etc/logrotate.d/vnctoken /etc/logrotate.d/

sudo cp etc/one/vnctoken-server.conf /etc/one/

sudo cp etc/systemd/system/vnctoken.service /etc/systemd/system/

sudo cp -a etc/systemd/system/opennebula-sunstone.service.wants /etc/systemd/system/

sudo systemctl daemon-reload

sudo systemctl restart opennebula-sunstone
```

## Usage

With the default configuration the service is listening on localhost, port 2644. The endpoint URL is http://localhost:2644/RPC2.

The XMLRPC endpoint is serving the following methods via both POST and GET requests.

The method response is a single parameter with the folloing common array

| Data Type | Description |
| --------- | ----------- |
| Boolean   | True or false whenever is successful or not. |
| String/Struct| If an error occurs this is the error message else it is a string with the response or Structure, described below. |
| Int | Error code. |

Data structure returned on success:

| Data Type | Variable | Description |
| --------- | -------- | ----------- |
| Int | VmId | VM ID |
| String | Host | The Host where the VM is running. |
| String | Type | The Graphics Type (only 'VNC' is supported). |
| String | Listen | The LISTEN element of the VM's GRAPHICS definition. |
| String | Password | VNC passsword. |
| Boolean | Wss | Websockets (false) or Secure Websockets (true) are set. |
| String | Token | The noVNC proxy token generated by the service. |


### one.vm.vnctoken

Accept the following arguments(OpenNebula's API definition was followed):

| Type | Data Type | Description |
| ---- | --------- | ----------- |
| IN | String | The session string. |
| IN | 	Int | The VM ID. |
| OUT  | Array  | Method response |

And returns 

### one.vm.vnctokenonly

Accept the following arguments(OpenNebula's API definition was followed):

| Type | Data Type | Description |
| ---- | --------- | ----------- |
| IN | String | The session string. |
| IN | 	Int | The VM ID. |
| OUT  | Array  | Method response |

And returns a string with the generated vnctoken

### one.vm.vnc

Accept the following arguments(OpenNebula's API definition was followed):

| Type | Data Type | Description |
| ---- | --------- | ----------- |
| IN | String | The session string. |
| IN | 	Int | The VM ID. |
| OUT  | Array  | Method response |

And returns a string with a XML holding same values as the Data structure described above

## nginx configuration examples

The following configuration will allow ssl access to the vnctoken service with https://SERVERNAME:2645/RPC2

```
upstream vncxmlrpc {
  server 127.0.0.1:2644;
}
server {
    listen       2645 ssl;
    listen       [::]:2645 ssl;
    server_name  SERVERNAME;
    root         /usr/share/nginx/html;
    access_log /var/log/nginx/vncxmlrpc-access.log;
    error_log /var/log/nginx/vncxmlrpc-error.log;
    location / {
        proxy_http_version 1.1;
        proxy_pass http://vncxmlrpc;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-FOR $proxy_add_x_forwarded_for;
        proxy_read_timeout 30s;
        proxy_buffering off;
    }
    error_page 404 /404.html;
        location = /40x.html {
    }
    error_page 500 502 503 504 /50x.html;
        location = /50x.html {
    }
    ssl_certificate /etc/letsencrypt/live/SERVERNAME/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/SERVERNAME/privkey.pem; # managed by Certbot
}
```

The service accept any URL starting with /RPC2 so it could be added on same port where the OpenNebula XMLRPC is proxied via Nginx. In the following example the OpenNebula XMLRPC is accessible with ssl with url _https://SERVERNAME:2634/RPC2_ and the vnctoken XMLRPC could be accessed via _https://SERVERNAME:2634/RPC2/vnctoken_ for example. This way only one port should be configured in the firewall to access both XMLRPC endpoints

```
##
## OpenNebula XML-RPC proxy (optional)
##
upstream onexmlrpc {
  server 127.0.0.1:2633;
}
upstream vncxmlrpc {
  server 127.0.0.1:2644;
}
server {
    listen       2634 ssl;
    listen       [::]:2634 ssl;
    server_name  SERVERNAME;
    root         /usr/share/nginx/html;
    location / {
        proxy_http_version 1.1;
        proxy_pass http://onexmlrpc;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-FOR $proxy_add_x_forwarded_for;
        proxy_read_timeout 180s;
        proxy_buffering off;
    }
    location /RPC2/vnctoken {
        proxy_http_version 1.1;
        proxy_pass http://vncxmlrpc;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-FOR $proxy_add_x_forwarded_for;
        proxy_read_timeout 30s;
        proxy_buffering off;
    }
    error_page 404 /404.html;
        location = /40x.html {
    }
    error_page 500 502 503 504 /50x.html;
        location = /50x.html {
    }
    ssl_certificate /etc/letsencrypt/live/SERVERNAME/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/SERVERNAME/privkey.pem; # managed by Certbot
}

```

A complete nginx configuration example could be found in _vnctoken.conf.nginx_ file.

