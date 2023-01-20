#!/bin/bash
# User must run the script as root
if [[ $EUID -ne 0 ]]; then
	echo "Please run this script as root"
	exit 1
fi
distro=$(awk -F= '/^NAME/{print $2}' /etc/os-release)
# This function installs v2fly/xray executables and creates an empty config
function install_v2ray {
	# At first install some stuff needed for this script
	apt update
	apt -y install jq curl wget unzip moreutils sqlite3
	# Get user's architecture
	local arch
	arch=$(uname -m)
	case $arch in
	"i386" | "i686") arch=1 ;;
	"x86_64") arch=2 ;;
	esac
	echo "1) 32-bit"
	echo "2) 64-bit"
	echo "3) arm-v5"
	echo "4) arm-v6"
	echo "5) arm-v7a"
	echo "6) arm-v8a"
	read -r -p "Select your architecture: " -e -i $arch arch
	case $arch in
	1) arch="32" ;;
	2) arch="64" ;;
	3) arch="arm32-v5" ;;
	4) arch="arm32-v6" ;;
	5) arch="arm32-v7a" ;;
	6) arch="arm64-v8a" ;;
	*)
		echo "$(tput setaf 1)Error:$(tput sgr 0) Invalid option"
		exit 1
		;;
	esac
	# Ask for xray or v2fly
	local xray_or_v2fly
	echo "1) xray"
	echo "2) v2fly"
	read -r -p "What do you want to install? " -e -i 1 xray_or_v2fly
	# Now download the executable
	local url
	case $xray_or_v2fly in
	1)
		url=$(wget -q -O- https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq --arg v "Xray-linux-$arch.zip" -r '.assets[] | select(.name == $v) | .browser_download_url')
		wget -O v2ray.zip "$url"
		unzip v2ray.zip xray -d /usr/local/bin/
		mv /usr/local/bin/xray /usr/local/bin/v2ray
		xray_or_v2fly='xray'
		;;
	2)
		url=$(wget -q -O- https://api.github.com/repos/v2fly/v2ray-core/releases/latest | jq --arg v "v2ray-linux-$arch.zip" -r '.assets[] | select(.name == $v) | .browser_download_url')
		wget -O v2ray.zip "$url"
		unzip v2ray.zip v2ray -d /usr/local/bin/
		xray_or_v2fly='v2fly'
		;;
	*)
		echo "$(tput setaf 1)Error:$(tput sgr 0) Invalid option"
		exit 1
		;;
	esac
	# Create the config file
	mkdir /usr/local/etc/v2ray
	echo '{"log":{"loglevel":"warning","access":"none"},"inbounds":[],"outbounds":[{"protocol":"freedom"}],"stats":{},"policy":{"levels":{"0":{"statsUserUplink":true,"statsUserDownlink":true}},"system":{"statsOutboundUplink":true,"statsOutboundDownlink":true}},"api":{"tag":"api","services":["StatsService"]},"routing":{"rules":[{"inboundTag":["api"],"outboundTag":"api","type":"field"}],"domainStrategy":"AsIs"}}' > /usr/local/etc/v2ray/config.json
	unzip v2ray.zip '*.dat' -d /usr/local/etc/v2ray
	touch "/usr/local/etc/v2ray/.$xray_or_v2fly"
	# Create the config file
	echo "[Unit]
Description=V2Ray Service
After=network.target nss-lookup.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/v2ray run -config /usr/local/etc/v2ray/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/v2ray.service
	systemctl daemon-reload
	systemctl enable v2ray
	systemctl start v2ray
	# Cleanup
	rm v2ray.zip
}

# Uninstalls v2ray and service
function uninstall_v2ray {
	# Remove firewall rules
	local to_remove_ports
	to_remove_ports=$(jq '.inbounds[] | select(.listen != "127.0.0.1") | .port' /usr/local/etc/v2ray/config.json)
	while read -r port; do
		if [[ $distro =~ "Ubuntu" ]]; then
			ufw delete allow "$port"/tcp
		elif [[ $distro =~ "Debian" ]]; then
			iptables -D INPUT -p tcp --dport "$port" --jump ACCEPT
			iptables-save >/etc/iptables/rules.v4
		fi
	done <<< "$to_remove_ports"
	# Stop and remove the service and files
	systemctl stop v2ray
	systemctl disable v2ray
	rm /usr/local/bin/v2ray /etc/systemd/system/v2ray.service
	rm -r /usr/local/etc/v2ray
	systemctl daemon-reload
}

# Returns the v2ray tls configuration.
# Generates tls certs or gets them from disk.
# Returns the TlsObject as TLS_SETTINGS variable.
function get_tls_config {
	# Get server name
	local servername
	read -r -p "Select your servername: " -e servername
	# Get cert
	local option certificate
	echo "	1) I already have certificate and private key"
	echo "	2) Create certificate and private key for me"
	read -r -p "What do you want to do? (select by number) " -e option
	case $option in
	1)
		local cert key
		read -r -p "Enter the path to your cert file: " -e cert
		read -r -p "Enter the path to your key file: " -e key
		certificate=$(jq -nc --arg cert "$cert" --arg key "$key" '{certificateFile: $cert, keyFile: $key}')
		;;
	2) certificate=$(v2ray tls cert --domain "$servername") ;;
	*)
		echo "$(tput setaf 1)Error:$(tput sgr 0) Invalid option"
		exit 1
		;;
	esac
	# Generate the config
	TLS_SETTINGS=$(jq -c --arg servername "$servername" '{serverName: $servername, certificates: [.]}' <<< "$certificate")
}

# Checks if the port is in use in inbound rules of v2ray.
# First argument must be the port number to check.
# Returns 0 if it's in use otherwise 1
function is_port_in_use_inbound {
	jq --arg port "$1" -e '.inbounds[] | select(.port == $port) | length > 0' /usr/local/etc/v2ray/config.json > /dev/null
}

# This function will check if api is enabled as a rule
function is_api_enabled {
	jq -e '.inbounds[] | select(.tag == "api") | length > 0' /usr/local/etc/v2ray/config.json > /dev/null
}

# This function will check if xray is installed. If true returns 0 otherwise (v2fly is installed)
# returns non zero.
function is_xray {
	v2ray version | grep xray
}

# Get port will get a port from user.
# It will also check if the port is valid and if another v2ray service is using it.
function get_port {
	local regex_number='^[0-9]+$'
	read -r -p "Select a port to proxy listen on it: " -e PORT
	if ! [[ $PORT =~ $regex_number ]]; then
		echo "$(tput setaf 1)Error:$(tput sgr 0) The port is not a valid number"
		exit 1
	fi
	if [ "$PORT" -gt 65535 ]; then
		echo "$(tput setaf 1)Error:$(tput sgr 0) Number must be less than 65536"
		exit 1
	fi
	# Check if the port is in use by another service of v2ray
	if is_port_in_use_inbound "$PORT"; then
		echo "$(tput setaf 1)Error:$(tput sgr 0) Port already in use"
		exit 1
	fi
}

# This function will print all inbound configs of installed v2ray server
function print_inbound {
	# Check zero length
	if jq -e '.inbounds | length == 0' /usr/local/etc/v2ray/config.json > /dev/null; then
		echo "No configured inbounds!"
		echo
		return
	fi
	# Print
	echo "Currently configured inbounds:"
	local inbounds
	inbounds=$(jq -c '.inbounds[]' /usr/local/etc/v2ray/config.json)
	local i=1
	# Loop over all inbounds
	while read -r inbound; do
		local line
		# Protocol
		line=$(jq -r '.protocol' <<< "$inbound")
		line+=" + "
		# Transport
		line+=$(jq -r '.streamSettings.network' <<< "$inbound")
		# TLS
		if [[ $(jq -r '.streamSettings.security' <<< "$inbound") == "tls" ]]; then
			line+=" + TLS"
		fi
		# Listening port
		line+=" ("
		line+=$(jq -r '"Listening on " + .listen + ":" + (.port | tostring)' <<< "$inbound")
		line+=")"
		# Done
		echo "$i) $line"
		i=$((i+1))
	done <<< "$inbounds"
	echo
}

# Gets the options to setup shadowsocks server and sends back the raw json in
# PROTOCOL_CONFIG variable
function configure_shadowsocks_settings {
	# Ask about method
	local method
	echo "	1) aes-128-gcm"
	echo "	2) aes-256-gcm"
	echo "	3) chacha20-poly1305"
	echo "	4) none"
	read -r -p "Select encryption method for shadowsocks: " -e -i "1" method
	case $method in
	1) method="aes-128-gcm" ;;
	2) method="aes-256-gcm" ;;
	3) method="chacha20-poly1305" ;;
	4)
		method="none"
		echo "$(tput setaf 3)Warning!$(tput sgr 0) none method must be combined with an encrypted trasport like TLS."
		;;
	*)
		echo "$(tput setaf 1)Error:$(tput sgr 0) Invalid option"
		exit 1
		;;
	esac
	# Ask about password
	local password
	read -r -p "Enter a password for shadowsocks. Leave blank for a random password: " password
	if [ "$password" == "" ]; then
		password=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 16 | head -n 1) # https://gist.github.com/earthgecko/3089509
		echo "$password was chosen."
	fi
	# Create the config file
	PROTOCOL_CONFIG=$(jq -nc --arg method "$method" --arg password "$password" '{method: $method, password: $password}')
}


# Adds and removes users from a user set of vmess or vless.
# First argument must be the initial value of the config.
# Second argument must be either vless or vmess.
# The config result is returned in an variable called PROTOCOL_CONFIG
function manage_vmess_vless_users {
	local config=$1
	local option id email
	while true; do
		echo "	1) View clients"
		echo "	2) Add random ID to config"
		echo "	3) Add custom ID to config"
		echo "	4) Delete ID from config"
		echo "	*) Back"
		read -r -p "What do you want to do? (select by number) " -e option
		case $option in
		1)
			jq -r '.[] | .email + " (" + .id + ")"' <<< "$config"
			;;
		2)
			id=$(v2ray uuid)
			read -r -p "Choose an email for this user. It could be an arbitrary email: " -e email
			config=$(jq -c --arg id "$id" --arg email "$email" '. += [{id: $id, email: $email}]' <<< "$config")
			;;
		3)
			read -r -p "Enter your uuid: " -e id
			read -r -p "Choose an email for this user. It could be an arbitrary email: " -e email
			config=$(jq -c --arg id "$id" --arg email "$email" '. += [{id: $id, email: $email}]' <<< "$config")
			;;
		4)
			local i=1
			local users
			users=$(jq -r '.[] | .email + " (" + .id + ")"' <<< "$config")
			while read -r user; do
				echo "$i) $user"
				i=$((i+1))
			done <<< "$users"
			read -r -p "Select an ID by its index to remove it: " -e option
			config=$(jq -c --arg index "$option" 'del(.[$index | tonumber - 1])' <<< "$config")
			;;
		*)
			PROTOCOL_CONFIG=$(jq -c '{clients: .}' <<< "$config")
			if [[ "$2" == "vless" ]]; then
				PROTOCOL_CONFIG=$(jq -c '. += {"decryption": "none"}' <<< "$PROTOCOL_CONFIG")
			fi
			break
		esac
	done
}

# Adds and removes users from a user set of trojan.
# First argument must be the initial value of the config.
# The config result is returned in an variable called PROTOCOL_CONFIG
function manage_trojan_users {
	local config=$1
	local option password email
	while true; do
		echo "	1) View clients"
		echo "	2) Add random password to config"
		echo "	3) Add custom password to config"
		echo "	4) Delete password from config"
		echo "	*) Back"
		read -r -p "What do you want to do? (select by number) " -e option
		case $option in
		1)
			jq -r '.[] | .email + " (" + .password + ")"' <<< "$config"
			;;
		2)
			password=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 16 | head -n 1)
			read -r -p "Choose an email for this user. It could be an arbitrary email: " -e email
			config=$(jq -c --arg password "$password" --arg email "$email" '. += [{password: $password, email: $email}]' <<< "$config")
			;;
		3)
			read -r -p "Enter your password: " -e password
			read -r -p "Choose an email for this user. It could be an arbitrary email: " -e email
			config=$(jq -c --arg password "$password" --arg email "$email" '. += [{password: $password, email: $email}]' <<< "$config")
			;;
		4)
			local i=1
			local users
			users=$(jq -r '.[] | .email + " (" + .password + ")"' <<< "$config")
			while read -r user; do
				echo "$i) $user"
				i=$((i+1))
			done <<< "$users"
			read -r -p "Select an password by its index to remove it: " -e option
			config=$(jq -c --arg index "$option" 'del(.[$index | tonumber - 1])' <<< "$config")
			;;
		*)
			PROTOCOL_CONFIG=$(jq -c '{clients: .}' <<< "$config")
			break
		esac
	done
}

# Call this function with first argument as user arrays to
# ask the user to choose one of the users. The uid of the user will be returned as
# USER_ID varible.
function choose_vless_vmess_user {
	# Print users
	local config=$1
	local i=1
	local configs option
	configs=$(jq -r '.[] | .email + " (" + .id + ")"' <<< "$config")
	echo "Here are the list of user ids for this inbound:"
	while read -r user; do
		echo "$i) $user"
		i=$((i+1))
	done <<< "$configs"
	read -r -p "Select a user by it's index: " -e option
	# Get the UID of the choosen user
	USER_ID=$(jq -r --arg index "$option" '.[$index | tonumber - 1].id' <<< "$config")
	if [[ "$USER_ID" == "" ]]; then
		echo "$(tput setaf 1)Error:$(tput sgr 0) Invalid index."
		exit 1
	fi
}

# Call this function with first argument as user arrays to
# ask the user to choose one of the users. The uid of the user will be returned as
# PASSWORD varible.
function choose_torjan_user {
	# Print users
	local config=$1
	local i=1
	local configs option
	configs=$(jq -r '.[] | .email + " (" + .password + ")"' <<< "$config")
	echo "Here are the list of passwords for this config:"
	while read -r user; do
		echo "$i) $user"
		i=$((i+1))
	done <<< "$configs"
	read -r -p "Select a user by it's index: " -e option
	# Get the UID of the choosen user
	PASSWORD=$(jq -r --arg index "$option" '.[$index | tonumber - 1].password' <<< "$config")
	if [[ "$PASSWORD" == "" ]]; then
		echo "$(tput setaf 1)Error:$(tput sgr 0) Invalid index."
		exit 1
	fi
}

# Adds an inbound rule to config file
function add_inbound_rule {
	# At first get the port of user
	get_port
	local port="$PORT"
	# Listen address
	local listen_address
	read -r -p "On what interface you want to listen?: " -e -i '0.0.0.0' listen_address
	# Get the service
	local protocol
	echo "	1) VMess"
	echo "	2) VLESS"
	echo "	3) Shadowsocks"
	echo "	4) SOCKS"
	echo "	5) Trojan"
	read -r -p "Select your protocol: " -e protocol
	case $protocol in
	1)
		protocol="vmess"
		manage_vmess_vless_users "[]" "vmess"
		;;
	2)
		protocol="vless"
		manage_vmess_vless_users "[]" "vless"
		;;
	3)
		protocol="shadowsocks"
		configure_shadowsocks_settings
		;;
	4)
		local option username password
		read -r -p "Do you want use username and password? (y/n) " -e -i "n" option
		if [[ "$option" == "y" ]]; then
			# For now, we only support one username and password. I doubt someone uses my script
			# for setting up a socks server with v2ray.
			read -r -p "Select a username: " -e username
			read -r -p "Select a password: " -e password
			PROTOCOL_CONFIG=$(jq -nc --arg user "$username" --arg pass "$password" '{auth:"password", accounts: [{user: $user, pass: $pass}]}')
		else
			PROTOCOL_CONFIG='{"auth":"noauth"}'
		fi
		;;
	5)
		protocol="trojan"
		manage_trojan_users "[]"
		;;
	*)
		echo "$(tput setaf 1)Error:$(tput sgr 0) Invalid option"
		exit 1
		;;
	esac
	# Get the transport
	local network network_path grpc_service_name
	echo "	1) Raw TCP"
	echo "	2) TLS"
	echo "	3) Websocket"
	echo "	4) Websocket + TLS"
	echo "	5) HTTP2 cleartext"
	echo "	6) HTTP2 + TLS"
	echo "	7) gRPC cleartext"
	echo "	8) gRPC + TLS"
	read -r -p "Select your transport: " -e network
	case $network in
	1) network='{"network":"tcp","security":"none"}' ;;
	2)
		get_tls_config
		network="{\"network\":\"tcp\",\"security\":\"tls\",\"tlsSettings\":$TLS_SETTINGS}"
		;;
	3)
		read -r -p "Select a path for websocket (do not use special characters execpt /): " -e -i '/' network_path
		network="{\"network\":\"ws\",\"security\":\"none\",\"wsSettings\":{\"path\":\"$network_path\"}}"
		;;
	4)
		get_tls_config
		read -r -p "Select a path for websocket (do not use special characters execpt /): " -e -i '/' network_path
		network="{\"network\":\"ws\",\"security\":\"tls\",\"wsSettings\":{\"path\":\"$network_path\"},\"tlsSettings\":$TLS_SETTINGS}"
		;;
	5)
		read -r -p "Select a path for http (do not use special characters execpt /): " -e -i '/' network_path
		network="{\"network\":\"h2\",\"security\":\"none\",\"httpSettings\":{\"path\":\"$network_path\"}}"
		;;
	6)
		get_tls_config
		read -r -p "Select a path for http (do not use special characters execpt /): " -e -i '/' network_path
		network="{\"network\":\"h2\",\"security\":\"tls\",\"httpSettings\":{\"path\":\"$network_path\"},\"tlsSettings\":$TLS_SETTINGS}"
		;;
	7)
		read -r -p "Select a service name for gRPC (do not use special characters): " -e grpc_service_name
		network="{\"network\":\"gun\",\"security\":\"none\",\"grpcSettings\":{\"serviceName\":\"$grpc_service_name\"}}"
		;;
	8)
		get_tls_config
		read -r -p "Select a service name for gRPC (do not use special characters): " -e grpc_service_name
		network="{\"network\":\"gun\",\"security\":\"tls\",\"grpcSettings\":{\"serviceName\":\"$grpc_service_name\"},\"tlsSettings\":$TLS_SETTINGS}"
		;;
	*)
		echo "$(tput setaf 1)Error:$(tput sgr 0) Invalid option"
		exit 1
		;;
	esac
	# Finally, create the config chunk
	local inbound
	inbound=$(jq -cn --arg listen "$listen_address" --argjson port "$port" --arg protocol "$protocol" --argjson settings "$PROTOCOL_CONFIG" --argjson network "$network" '{listen: $listen, port: $port, protocol: $protocol, settings: $settings, streamSettings: $network}')
	jq --argjson v "$inbound" '.inbounds[.inbounds | length] |= $v' /usr/local/etc/v2ray/config.json | sponge /usr/local/etc/v2ray/config.json
	echo "Config added!"
	# Restart the server and add the rule to firewall
	systemctl restart v2ray
	if [[ "$listen_address" != "127.0.0.1" ]]; then
		if [[ $distro =~ "Ubuntu" ]]; then
			ufw allow "$port"/tcp
		elif [[ $distro =~ "Debian" ]]; then
			iptables -A INPUT -p tcp --dport "$port" --jump ACCEPT
			iptables-save >/etc/iptables/rules.v4
		fi
	fi
}

# Removes one inbound rule from configs
function remove_inbound_rule {
	local option port
	read -r -p "Select an inbound rule to remove by its index: " -e option
	# Remove the firewall rule
	port=$(jq -r --arg index "$option" '.inbounds[$index | tonumber - 1].port' /usr/local/etc/v2ray/config.json)
	if [[ "$port" != "null" ]]; then
		if [[ $distro =~ "Ubuntu" ]]; then
			ufw delete allow "$port"/tcp
		elif [[ $distro =~ "Debian" ]]; then
			iptables -D INPUT -p tcp --dport "$port" --jump ACCEPT
			iptables-save >/etc/iptables/rules.v4
		fi
	fi
	# Change the config
	jq -c --arg index "$option" 'del(.inbounds[$index | tonumber - 1])' /usr/local/etc/v2ray/config.json | sponge /usr/local/etc/v2ray/config.json
	systemctl restart v2ray
}

# This function will act as a user manager for vless/vmess/torjan inbounds
function edit_config {
	# Ask user to choose from vless/vmess configs
	local option
	read -r -p "Select a vless/vmess rule to edit it by its index: " -e option
	# Check if it's vless/vmess and open menu
	local protocol clients
	clients="$(jq -c --arg index "$option" '.inbounds[$index | tonumber - 1].settings.clients' /usr/local/etc/v2ray/config.json)"
	protocol=$(jq -r --arg index "$option" '.inbounds[$index | tonumber - 1].protocol' /usr/local/etc/v2ray/config.json)
	case $protocol in
	"vless"|"vmess")
		manage_vmess_vless_users "$clients" "$protocol"
		;;
	"trojan")
		manage_trojan_users "$clients"
		;;
	*)
		echo "$(tput setaf 1)Error:$(tput sgr 0) Selected inbound is not vless nor vmess"
		exit 1
		;;
	esac
	# Save
	jq --argjson protocol_config "$PROTOCOL_CONFIG" --arg index "$option" '.inbounds[$index | tonumber - 1] += {settings: $protocol_config}' /usr/local/etc/v2ray/config.json | sponge /usr/local/etc/v2ray/config.json
	systemctl restart v2ray
}

# Generates a client config for an inbound and user
function generate_client_config {
	local client_base='{"log":{"loglevel":"info"},"inbounds":[{"listen":"127.0.0.1","port":"10808","protocol":"socks","settings":{"udp":true}},{"listen":"127.0.0.1","port":"10809","protocol":"http"}]}'
	local outbound_rule outbound_settings
	# Get IP of server
	local public_ip curl_exit_status
	public_ip="$(curl https://api.ipify.org -sS)"
	curl_exit_status=$?
	[ $curl_exit_status -ne 0 ] && public_ip="YOUR_IP"
	# Get the rule
	local option
	read -r -p "Select a rule to generate the config of it by its index: " -e option
	# Based on protocol create the config file
	local protocol port clients
	protocol=$(jq -r --arg index "$option" '.inbounds[$index | tonumber - 1].protocol' /usr/local/etc/v2ray/config.json)
	port=$(jq -r --arg index "$option" '.inbounds[$index | tonumber - 1].port' /usr/local/etc/v2ray/config.json)
	clients=$(jq -c --arg index "$option" '.inbounds[$index | tonumber - 1].settings.clients' /usr/local/etc/v2ray/config.json)
	case $protocol in
	"vless"|"vmess")
		choose_vless_vmess_user "$clients"
		outbound_settings=$(jq -n --arg address "$public_ip" --arg port "$port" --arg id "$USER_ID" '{address: $address, port: ($port | tonumber), users: [{id: $id}]}')
		if [[ "$protocol" == "vless" ]]; then
			outbound_settings=$(jq '.users[0] += {encryption: "none"}' <<< "$outbound_settings")
		fi
		outbound_settings=$(jq -c '{vnext: [.]}' <<< "$outbound_settings")
		;;
	"trojan")
		choose_torjan_user "$clients"
		outbound_settings=$(jq -n --arg address "$public_ip" --arg port "$port" --arg password "$PASSWORD" '{servers: [{address: $address, port: ($port | tonumber), password: $password}]}')
		;;
	*)
		echo "$(tput setaf 1)Error:$(tput sgr 0) This protocol is not currently supported by script..."
		exit 1
		;;
	esac
	# We put the transport settings just like the one in server.
	local transport_settings
	transport_settings=$(jq -c --arg index "$option" '.inbounds[$index | tonumber - 1].streamSettings' /usr/local/etc/v2ray/config.json)
	outbound_rule=$(jq -n --arg protocol "$protocol" --argjson settings "$outbound_settings" --argjson transport "$transport_settings" '{protocol: $protocol, settings: $settings, streamSettings: $transport}')
	# Save the file
	local filename
	read -r -p "Enter a filename to save the client file: " -e filename
	# At last, we compile the result json and save it to file
	jq --argjson outbound "$outbound_rule" '.outbounds = [$outbound]' <<< "$client_base" > "$filename"
	chmod 666 "$filename"
}

# This function will enable the api if it is not enabled 
function manage_api {
	# Enable API if needed
	if ! is_api_enabled; then
		echo "API is not enabled. To enable it, please select a loopback port:"
		get_port
		# Add the rule
		new_rule=$(jq --argjson port "$PORT" '.port |= $port' <<< '{"listen":"127.0.0.1","protocol":"dokodemo-door","settings":{"address":"127.0.0.1"},"tag":"api"}')
		jq --argjson api "$new_rule" '(.inbounds += [$api])' /usr/local/etc/v2ray/config.json | sponge /usr/local/etc/v2ray/config.json
		systemctl restart v2ray
	fi
	# Get port
	local port
	port=$(jq '.inbounds[] | select(.tag == "api") | .port' /usr/local/etc/v2ray/config.json)
	# Request the data
	local method data
	if [[ is_xray ]]; then # xray is statusquery while v2fly is stats
		method="statsquery"
	else
		method="stats"
	fi
	data=$(v2ray api "$method" --server="127.0.0.1:$port" | jq -c '.stat | (.[].value |= tonumber) | (.[].name |= split(">>>")) | group_by(.name[1]) | (.[] |= {download: (if .[0].name[3] == "downlink" then .[0].value else .[1].value end), upload: (if .[0].name[3] == "downlink" then .[1].value else .[0].value end), name: .[0].name[1]}) | .[]')
	# Create the database
	sqlite3 /usr/local/etc/v2ray/usage.db 'CREATE TABLE IF NOT EXISTS v2ray_traffic(
		insert_time INTEGER NOT NULL,
		username TEXT NOT NULL,
		download INTEGER NOT NULL,
		upload INTEGER NOT NULL,
		PRIMARY KEY (insert_time, username)
	)'
	# Create the query
	local query_buffer=""
	while IFS=$"\n" read -r c; do
		query_buffer+=$(printf '(%d, "%s", %d, %d),' "$(date +%s)" "$(jq -r .name <<< "$c")" "$(jq -r .download <<< "$c")" "$(jq -r .upload <<< "$c")") 
	done <<< "$data"
	query_buffer=${query_buffer::-1} # remove last ,
	query_buffer="INSERT INTO v2ray_traffic VALUES $query_buffer"
	# Save data in database
	sqlite3 /usr/local/etc/v2ray/usage.db "$query_buffer"
	# Restart v2ray to reset data
	systemctl restart v2ray
	# Get data from database
	sqlite3 -header -column /usr/local/etc/v2ray/usage.db 'SELECT * FROM (SELECT username AS Email, "↓" || (SUM(download) / 1024 / 1024) || "MB" AS Download, "↑" || (SUM(upload) / 1024 / 1024) || "MB" AS Upload, "↕️" || (SUM(upload + download) / 1024 / 1024) || "MB" AS Total FROM v2ray_traffic GROUP BY username ORDER BY SUM(upload + download) DESC) UNION ALL SELECT "Total", "↓" || (SUM(download) / 1024 / 1024) || "MB", "↑" || (SUM(upload) / 1024 / 1024) || "MB", "↕️" || (SUM(upload + download) / 1024 / 1024) || "MB" FROM v2ray_traffic'
}

# Shows a menu to edit user
function main_menu {
	local option
	# Get current inbound stuff
	print_inbound
	# Main menu
	echo "What do you want to do?"
	echo "	1) Add rule"
	echo "	2) Edit VMess/VLess/Trojan accounts"
	echo "	3) Show data usage of users"
	echo "	4) Generate client config"
	echo "	5) Delete rule"
	echo "	6) Uninstall v2ray"
	echo "	*) Exit"
	read -r -p "Please enter an option: " option
	case $option in
	1) add_inbound_rule ;;
	2) edit_config ;;
	3) manage_api ;;
	4) generate_client_config ;;
	5) remove_inbound_rule ;;
	6) uninstall_v2ray ;;
	esac
}

# Check if v2ray is installed
if [ ! -f /usr/local/etc/v2ray/config.json ]; then
	echo "It looks like that v2ray is not installed on your system."
	read -n 1 -s -r -p "Press any key to install it or Ctrl+C to cancel..."
	install_v2ray
fi

# Open main menu
clear
echo "V2Fly/Xray installer script by Hirbod Behnam"
echo "Source at https://github.com/HirbodBehnam/V2Ray-Installer"
echo
main_menu
