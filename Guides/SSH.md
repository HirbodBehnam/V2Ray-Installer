# Get SOCKS5 Proxy from SSH

You can get a socks proxy if you do have SSH access to a server. But to do so, it's better to create a user
which only has no shell access. To create such a user, use the following command:

```bash
useradd -m -s /bin/false proxyuser
```

The last argument is the username of the new user. With `-m` command we say that we want a home directory (we will use SSH key) and with `-s /bin/false` we deny shell access for this user.

Now we want to add a SSH key to this user. To do so, create a SSH key on your OWN computer. Copy the public key to `/home/proxyuser/.ssh/authorized_keys`. You can create ssh key with `ssh-keygen -t ecdsa-sha2-nistp256` command or PuTTYgen. Some programs like HTTP Injector does not work with newer signature algorithms like Ed25519. So I recommend sticking to ECDSA.

Before connecting to server, we need to fix the permissions of `/home/proxyuser/.ssh/authorized_keys` file to be accessible only to our new user. To do so, use the following commands:

```bash
chmod -R 700 /home/proxyuser/.ssh/
chown -R proxyuser:proxyuser /home/proxyuser/.ssh/
```

At last, we want to connect to our server. From command line user the following command: (You might also specify the ssh key with `-i` flag)

```bash
ssh -D 1080 -N proxyuser@1.1.1.1
```

This will open a socks proxy on port 1080. The `-N` command tells SSH to do not execute the shell and thus the shell wont close.

If you want to create the tunnel using putty, add the port in `Connection -> SSH -> Tunnels`. Choose `Dynamic` and a random source port like 1080 and click on add. Then in `Connection -> SSH`, check `Don't start a shell or command at all`.