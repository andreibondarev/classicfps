extends MultiplayerPeerExtension

## Host-side peer that serves several transports as one session: desktop
## clients over ENet (UDP) and browser clients over WebSocket, which cannot
## send raw UDP. SceneMultiplayer sees a single server; every remote peer ID is
## owned by exactly one transport, and packets are routed back through it.
##
## Browser peers inherit WebSocket's reliable-ordered delivery even for RPCs
## marked unreliable; desktop peers keep ENet's per-channel modes.

var _transports: Array[MultiplayerPeer] = []
var _owners: Dictionary = {}
var _max_peers := 0
var _target_peer := 0
var _transfer_mode := TRANSFER_MODE_RELIABLE
var _transfer_channel := 0
var _refusing := false


func _init(max_peers: int) -> void:
	_max_peers = max_peers


## Adds a transport that has already started listening (create_server OK).
func add_transport(transport: MultiplayerPeer) -> void:
	_transports.append(transport)
	transport.peer_connected.connect(_on_transport_peer_connected.bind(transport))
	transport.peer_disconnected.connect(_on_transport_peer_disconnected)


func transport_for_peer(peer_id: int) -> MultiplayerPeer:
	return _owners.get(peer_id) as MultiplayerPeer


func _on_transport_peer_connected(peer_id: int, transport: MultiplayerPeer) -> void:
	# Each transport draws its own random IDs. A collision, or a connection
	# beyond the shared session limit, is dropped before the game sees it.
	if _refusing or _owners.has(peer_id) or _owners.size() >= _max_peers:
		transport.disconnect_peer(peer_id, true)
		return
	_owners[peer_id] = transport
	peer_connected.emit(peer_id)


func _on_transport_peer_disconnected(peer_id: int) -> void:
	if _owners.erase(peer_id):
		peer_disconnected.emit(peer_id)


func _poll() -> void:
	for transport in _transports:
		transport.poll()


func _next_source() -> MultiplayerPeer:
	for transport in _transports:
		while transport.get_available_packet_count() > 0:
			# A packet that arrives in the same poll as its sender's dropped
			# connection must not reach the game under an unowned ID.
			if _owners.get(transport.get_packet_peer()) == transport:
				return transport
			transport.get_packet()
	return null


func _get_available_packet_count() -> int:
	if _next_source() == null:
		return 0
	var count := 0
	for transport in _transports:
		count += transport.get_available_packet_count()
	return count


# SceneMultiplayer asks for the next packet's peer, channel and mode before
# reading it, so these peek at the same transport _get_packet_script drains.
func _get_packet_peer() -> int:
	var source := _next_source()
	return source.get_packet_peer() if source != null else 0


func _get_packet_channel() -> int:
	var source := _next_source()
	return source.get_packet_channel() if source != null else 0


func _get_packet_mode() -> TransferMode:
	var source := _next_source()
	return source.get_packet_mode() if source != null else TRANSFER_MODE_RELIABLE


func _get_packet_script() -> PackedByteArray:
	var source := _next_source()
	if source == null:
		return PackedByteArray()
	return source.get_packet()


func _put_packet_script(buffer: PackedByteArray) -> Error:
	var result := OK
	if _target_peer > 0:
		var owner := transport_for_peer(_target_peer)
		if owner == null:
			return ERR_INVALID_PARAMETER
		return _send(owner, _target_peer, buffer)
	# 0 broadcasts; -id broadcasts to everyone except id.
	var excluded := -_target_peer
	for transport in _transports:
		var target := -excluded if excluded > 0 and transport_for_peer(excluded) == transport else 0
		var error := _send(transport, target, buffer)
		if error != OK:
			result = error
	return result


func _send(transport: MultiplayerPeer, target: int, buffer: PackedByteArray) -> Error:
	transport.set_target_peer(target)
	transport.transfer_mode = _transfer_mode
	transport.transfer_channel = _transfer_channel
	return transport.put_packet(buffer)


func _set_target_peer(peer_id: int) -> void:
	_target_peer = peer_id


func _set_transfer_mode(mode: TransferMode) -> void:
	_transfer_mode = mode


func _get_transfer_mode() -> TransferMode:
	return _transfer_mode


func _set_transfer_channel(channel: int) -> void:
	_transfer_channel = channel


func _get_transfer_channel() -> int:
	return _transfer_channel


func _get_unique_id() -> int:
	return 1


func _is_server() -> bool:
	return true


func _is_server_relay_supported() -> bool:
	return true


func _get_connection_status() -> ConnectionStatus:
	return CONNECTION_CONNECTED if not _transports.is_empty() else CONNECTION_DISCONNECTED


func _get_max_packet_size() -> int:
	# World snapshots are chunked well below every transport's limit.
	return 1 << 16


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable
	for transport in _transports:
		transport.refuse_new_connections = enable


func _is_refusing_new_connections() -> bool:
	return _refusing


func _disconnect_peer(peer_id: int, force: bool) -> void:
	var owner := transport_for_peer(peer_id)
	if owner != null:
		owner.disconnect_peer(peer_id, force)
	if force and _owners.erase(peer_id):
		peer_disconnected.emit(peer_id)


func _close() -> void:
	for transport in _transports:
		transport.close()
	_transports.clear()
	_owners.clear()
