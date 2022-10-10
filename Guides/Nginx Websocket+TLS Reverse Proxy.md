# Nginx Reverse Proxy for Websocket+TLS

In some cases, you want to use Nginx to reverse proxy your v2ray traffic to v2ray server. This reduces the chances of your server being detected.

## Setting up V2ray on Server

At first, we shall setup the v2ray server. To do so, use the script. For listen address use `127.0.0.1` and for port use something other than 443 or 80. Choose a protocol you desire. The important point is that you should choose raw websocket instead of websocket + TLS for transport. This is because Nginx will handle the TLS for us and will forward the decrypted traffic to v2ray.

Also take a note from path of websocket because we are going to need it later. For example, I use `/events`.

## Setting up Nginx on Server

To start, install Nginx from your package manager. Next, you need certificates to enable TLS on Nginx. You can either use certbot to get a signed certificate if you have a domain or use the following command I found on [StackOverflow](https://stackoverflow.com/a/10176685/4213397) to create a self signed certificate yourself:
```bash
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -sha256 -days 365 -nodes
```
If you want to generate a self signed certificate, I recommend you to don't use your real email address. As well as I recommend you to set common name to a real website domain. For example you can use `www.google.com`.

Then edit `/etc/nginx/sites-available/default` which is the configuration of Nginx. I recommend making a backup from it before editing it.

Here is an example of full config which I use and I stole from [v2fly guideline](https://guide.v2fly.org/advanced/wss_and_web.html#%E6%9C%8D%E5%8A%A1%E5%99%A8%E9%85%8D%E7%BD%AE).

```
server {
        listen 443 ssl http2;
        listen [::]:443 ssl http2;
        server_name your.server.name;

        ssl_certificate /opt/certs/cert.pem;
        ssl_certificate_key /opt/certs/key.pem;

        ssl_protocols TLSv1.2 TLSv1.3;

        root /var/www/html;
        index index.html index.htm index.nginx-debian.html;

        location /events {
            if ($http_upgrade != "websocket") {
                return 404;
            }
            proxy_redirect off;
            proxy_pass http://127.0.0.1:12345;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }

        location / {
                try_files $uri $uri/ =404;
        }
}


server {
        listen 80 default_server;
        listen [::]:80 default_server;
        return 301 https://$host$request_uri;
}
```

Here you need to change 4 things.

1. You need to change `server_name` to match the common name you selected in openssl or your real domain address.
2. `ssl_certificate` and `ssl_certificate_key` must be changed to match the path of your ssl certificate and key.
3. `/event` must be changed to your the path you choose when configuring the v2ray server.
4. `http://127.0.0.1:12345`'s port must be changed to port you choose when configuring the v2ray server.

After that, save the config file and run `nginx -t`. This will test the Nginx configuration. You should see a message like this:

```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

At last, use `systemctl restart nginx` to restart the Nginx and apply the configs.

You can check if Nginx is running by entering your IP address (or domain if you had one) in browser address bar and check if it opens Nginx welcome the page.

