extends SceneTree

## The browser player's real address arrives in the proxy's ?client_ip= query
## (deploy/Caddyfile). It must only be trusted from a loopback-bound listener.

var _failures := 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FORWARDED ADDRESS: " + message)


func _initialize() -> void:
	var session: Node = root.get_node("NetworkSession")
	session.web_socket_bind_address = "127.0.0.1"
	_check(session.forwarded_client_address("127.0.0.1", "ws://127.0.0.1:27448/ws?client_ip=203.0.113.9") == "203.0.113.9",
		"IPv4 from the proxy is trusted")
	_check(session.forwarded_client_address("127.0.0.1", "/ws?client_ip=2001%3Adb8%3A%3A1") == "2001:db8::1",
		"IPv6 is URL-decoded")
	_check(session.forwarded_client_address("127.0.0.1", "/ws?client_ip=not-an-ip") == "", "garbage is rejected")
	_check(session.forwarded_client_address("127.0.0.1", "/ws") == "", "no query, no address")
	_check(session.forwarded_client_address("198.51.100.4", "/ws?client_ip=203.0.113.9") == "",
		"a non-loopback connection cannot claim an address")
	session.web_socket_bind_address = "*"
	_check(session.forwarded_client_address("127.0.0.1", "/ws?client_ip=203.0.113.9") == "",
		"a publicly bound listener never trusts the query")
	if _failures == 0:
		print("NETWORK_FORWARDED_ADDRESS_PASS")
	quit(_failures)
