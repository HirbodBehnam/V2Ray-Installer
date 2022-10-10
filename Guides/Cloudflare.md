# Cloudflare CDN
You can use Cloudflare CDN to mask your server's IP address and sometimes improve the speed of your VPN.

## Requirements

* A domain
* Cloudflare account (free account works well)

## Setting up Server

Cloudflare can bypass websocket and gRPC traffic. Websocket works with or without TLS however I recommend using it.

There is no need to setup Nginx as reverse proxy of v2ray.

If you want to use gRPC as transport, your server MUST listen on port 443. For websocket, depending on if your server uses TLS or not, use one of the ports specified in [this](https://developers.cloudflare.com/fundamentals/get-started/reference/network-ports/) document. For example I use port 8080 for raw websocket and 2053 for TLS + websocket.

You can simply setup the server with script. Also, there is no need for a trusted certificate; Just use a self signed certificate (which script generates it for you).

## Setting up Cloudflare

In cloudflare, at first register your domain. Then create a subdomain and enable the cloudflare proxy.

![cf](https://i.imgur.com/D4w4d4u.jpg)

Then go to SSL/TLS tab and choose Full as encryption mode. Choose Full even when you want to use bare websocket without TLS.

![ssl-cf](https://i.imgur.com/M6MwgXK.jpg)

At last, go to Network tab and enable gRPC and Websocket. After that you are good to go!

![ws-grpc-settings](https://i.imgur.com/vZyBCpt.jpg)

## Client Settings

From client side, just make sure that SNI, address and websocket host (if you use websocket) is set to your domain address. The rest should be just like what you would use to connect to your server without CDN.