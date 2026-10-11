#!/bin/sh

# ip.gsh - Gopherbot shell plugin to report the robot's external IP address using ip.me

default_config() {
cat <<'EOF'
AllChannels: true
AllowedPrivateCommands:
- ip
Commands:
- Command: ip
  SimpleMatcher: "{what is|whats|what's|show|get} {my|the|your} {external|public|current} ip {address}"
  Usage: "ip"
  Summary: "get Floyd's current external IP address via ip.me"
  Keywords: [ "ip", "address", "external", "public", "ip.me" ]
  Examples:
  - "(alias) ip"
  - "(alias) external ip"
  - "(bot) what's your external ip?"
- Command: ip
  SimpleMatcher: "whatsmyip"
  Usage: "whatsmyip"
  Summary: "get Floyd's current external IP address via ip.me"
  Keywords: [ "ip", "whatsmyip" ]
  Examples:
  - "(alias) whatsmyip"
EOF
}

command=${1:-}
shift 2>/dev/null || true

case "$command" in
	_configure)
		default_config
		exit 0
		;;
	_init)
		exit 0
		;;
	ip)
		export PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}"
		if ! which curl >/dev/null 2>&1; then
			Log error "curl not found in PATH"
			say "Sorry, curl is not available to check the external IP address."
			exit $PLUGRET_Fail
		fi

		ip=$(curl -s -f -m 5 https://ip.me 2>/dev/null || curl -s -f -m 5 http://ip.me 2>/dev/null)
		ip=$(echo "$ip" | tr -d ' \r\n')

		if [ -n "$ip" ]; then
			say "My external IP address is $ip"
			exit $PLUGRET_Normal
		else
			Log error "Failed to retrieve external IP from ip.me"
			say "Sorry, I was unable to retrieve my external IP address from ip.me."
			exit $PLUGRET_Normal
		fi
		;;
	*)
		exit $PLUGRET_NotFound
		;;
esac
