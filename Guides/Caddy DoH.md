# Reverse Proxy Quad9 DoH with Caddy
DoH of popular sites might be blocked in some countries. But you can setup a DoH reverse proxy on your server to forward your queries to Quad9.

## Server

Setting it up is pretty straightforward. You just need to configure Caddy like this:

```
my.domain.com {
	tls cert.pem key.pem
	handle_path /doh/* {
		reverse_proxy https://dns.quad9.net:5053
	}
	root * /var/www/html
	file_server
}
```

Then you can test it with this command:
```bash
curl -v https://my.domain.com/doh/dns-query?name=google.com
```
You can even put your server behind Cloudflare to protect it from IP blocking. I also use a non-trivial path of `/doh/dns-query` to block active probings.

## Client
For client, I use DNSCrypt to connect to my own server's DoH. To configure DNSCrypt to use your server's DoH, at first go to [this](https://dnscrypt.info/stamps/) link and fill it like this:
```
Protocol: DoH
Hostname: my.domain.com
Path: /doh/dns-query
```
This will give you a stamp link. Copy it and open DNSCrypt's configuration. At the end, you should see `[static]` entry. Add these lines below it:
```
[static.'myserver']
stamp = 'sdns://...'
```
Where stamp is the url which the site gave you.

You might also want to disable all other resolvers. To do so, comment out everything in `[sources]` entry.