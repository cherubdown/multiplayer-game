extends RefCounted
## A small blocking PostgreSQL client speaking the v3 wire protocol over TCP,
## with optional TLS. Enough for the server's own queries: SCRAM-SHA-256, MD5
## or cleartext login, parameterized queries (values are sent separately from
## the SQL, so they can't inject SQL) and plain multi-statement scripts.
##
## Calls block until the database answers, so run them off the main thread
## (see AccountWorker).
##
## Connect with a URL like libpq's:
##   postgres://user:password@host:5432/dbname?sslmode=require
## sslmode is disable, prefer (the default: TLS if the server offers it),
## require (TLS without checking the certificate) or verify-full (TLS with the
## certificate checked against sslrootcert, a PEM file, or Godot's CA bundle).

const PROTOCOL_VERSION := 196608  # 3.0
const SSL_REQUEST_CODE := 80877103

const OID_BOOL := 16
const OID_INT8 := 20
const OID_INT2 := 21
const OID_INT4 := 23
const OID_FLOAT4 := 700
const OID_FLOAT8 := 701

## Milliseconds to wait for the network before giving up on a call.
var timeout_ms := 10000

var _tcp: StreamPeerTCP
var _tls: StreamPeerTLS
var _stream: StreamPeer
var _inbox := PackedByteArray()
var _crypto := Crypto.new()


## Splits a postgres:// URL into host, port, user, password, dbname, sslmode
## and sslrootcert. Returns an empty Dictionary if it isn't one.
static func parse_url(url: String) -> Dictionary:
	url = url.strip_edges()
	var scheme_end := url.find("://")
	if scheme_end < 0 or not url.substr(0, scheme_end) in ["postgres", "postgresql"]:
		return {}
	var rest := url.substr(scheme_end + 3)
	var query := ""
	if "?" in rest:
		query = rest.get_slice("?", 1)
		rest = rest.get_slice("?", 0)
	var config := { "host": "localhost", "port": 5432, "user": "", "password": "", "dbname": "", "sslmode": "prefer", "sslrootcert": "" }
	var slash := rest.find("/")
	if slash >= 0:
		config["dbname"] = rest.substr(slash + 1).uri_decode()
		rest = rest.substr(0, slash)
	var at := rest.rfind("@")
	if at >= 0:
		var userinfo := rest.substr(0, at)
		rest = rest.substr(at + 1)
		config["user"] = userinfo.get_slice(":", 0).uri_decode()
		if ":" in userinfo:
			config["password"] = userinfo.substr(userinfo.find(":") + 1).uri_decode()
	var colon := rest.rfind(":")
	if colon >= 0 and not rest.ends_with("]"):
		if not rest.substr(colon + 1).is_valid_int():
			return {}
		config["port"] = int(rest.substr(colon + 1))
		rest = rest.substr(0, colon)
	if rest != "":
		config["host"] = rest.trim_prefix("[").trim_suffix("]")
	for pair in query.split("&", false):
		var key := pair.get_slice("=", 0)
		if config.has(key) and key in ["sslmode", "sslrootcert", "dbname", "user", "password", "host"]:
			config[key] = pair.get_slice("=", 1).uri_decode()
	if config["dbname"] == "":
		config["dbname"] = config["user"]
	return config


## Connects and logs in. Returns "" on success or what went wrong.
func connect_to(url: String) -> String:
	close()
	var config := parse_url(url)
	if config.is_empty():
		return "The database URL isn't a postgres:// URL."
	if not config["sslmode"] in ["disable", "prefer", "require", "verify-full"]:
		return "sslmode must be disable, prefer, require or verify-full."

	var addresses := PackedStringArray([config["host"]])
	if not config["host"].is_valid_ip_address():
		# "localhost" can be both ::1 and 127.0.0.1; try each.
		addresses = IP.resolve_hostname_addresses(config["host"])
		if addresses.is_empty():
			return "Could not resolve the database host %s." % config["host"]
	for address in addresses:
		_tcp = StreamPeerTCP.new()
		_tcp.big_endian = true
		if _tcp.connect_to_host(address, config["port"]) != OK:
			continue
		var deadline := Time.get_ticks_msec() + timeout_ms
		while _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < deadline:
			OS.delay_msec(1)
			_tcp.poll()
		if _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
	if _tcp == null or _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		close()
		return "Could not connect to the database at %s:%d." % [config["host"], config["port"]]
	_stream = _tcp

	if config["sslmode"] != "disable":
		var err := _start_tls(config)
		if err != "":
			close()
			return err

	var err := _login(config)
	if err != "":
		close()
	return err


func is_open() -> bool:
	if _tcp == null:
		return false
	_tcp.poll()
	if _tls != null:
		if _tls.get_status() != StreamPeerTLS.STATUS_CONNECTED:
			return false
		_tls.poll()
		return _tls.get_status() == StreamPeerTLS.STATUS_CONNECTED
	return _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED


func close() -> void:
	if _stream != null and is_open():
		_send(_message("X", PackedByteArray()))
	if _tls != null:
		_tls.disconnect_from_stream()
	if _tcp != null:
		_tcp.disconnect_from_host()
	_tls = null
	_tcp = null
	_stream = null
	_inbox.clear()


## Runs one SQL statement with $1, $2... filled from params (null, bool,
## numbers or strings). Returns { rows: Array[Dictionary], error: String,
## code: String (the SQLSTATE), connection_lost: bool }.
func query(sql: String, params: Array = []) -> Dictionary:
	var result := { "rows": [], "error": "", "code": "", "connection_lost": false }
	if not is_open():
		result["error"] = "Not connected to the database."
		result["connection_lost"] = true
		return result

	var parse := StreamPeerBuffer.new()
	parse.big_endian = true
	_put_cstring(parse, "")
	_put_cstring(parse, sql)
	parse.put_16(0)

	var bind := StreamPeerBuffer.new()
	bind.big_endian = true
	_put_cstring(bind, "")
	_put_cstring(bind, "")
	bind.put_16(0)  # every parameter in text format
	bind.put_16(params.size())
	for value in params:
		if value == null:
			bind.put_32(-1)
			continue
		var text := ("true" if value else "false") if value is bool else str(value)
		var bytes := text.to_utf8_buffer()
		bind.put_32(bytes.size())
		bind.put_data(bytes)
	bind.put_16(0)  # every result column in text format

	var describe := PackedByteArray([ord("P"), 0])
	var execute := StreamPeerBuffer.new()
	execute.big_endian = true
	_put_cstring(execute, "")
	execute.put_32(0)

	var out := PackedByteArray()
	out.append_array(_message("P", parse.data_array))
	out.append_array(_message("B", bind.data_array))
	out.append_array(_message("D", describe))
	out.append_array(_message("E", execute.data_array))
	out.append_array(_message("S", PackedByteArray()))
	if not _send(out):
		result["error"] = "Lost the connection to the database."
		result["connection_lost"] = true
		return result
	return _collect(result)


## Runs one or more ;-separated statements without parameters, such as a
## schema migration. Returns the same Dictionary as query(), without rows.
func execute(sql: String) -> Dictionary:
	var result := { "rows": [], "error": "", "code": "", "connection_lost": false }
	if not is_open():
		result["error"] = "Not connected to the database."
		result["connection_lost"] = true
		return result
	var body := StreamPeerBuffer.new()
	_put_cstring(body, sql)
	if not _send(_message("Q", body.data_array)):
		result["error"] = "Lost the connection to the database."
		result["connection_lost"] = true
		return result
	return _collect(result)


# --- Connection setup --------------------------------------------------------

func _start_tls(config: Dictionary) -> String:
	var request := StreamPeerBuffer.new()
	request.big_endian = true
	request.put_32(8)
	request.put_32(SSL_REQUEST_CODE)
	if not _send(request.data_array):
		return "Lost the connection to the database."
	var answer := _read_exact(1)
	if answer.is_empty():
		return "Lost the connection to the database."
	if answer[0] != ord("S"):
		if config["sslmode"] == "prefer":
			return ""
		return "The database doesn't accept TLS connections (sslmode=%s)." % config["sslmode"]

	var options: TLSOptions
	var root: X509Certificate = null
	if config["sslrootcert"] != "":
		root = X509Certificate.new()
		if root.load(config["sslrootcert"]) != OK:
			return "Could not load sslrootcert %s." % config["sslrootcert"]
	if config["sslmode"] == "verify-full":
		options = TLSOptions.client(root)
	else:
		options = TLSOptions.client_unsafe(root)
	_tls = StreamPeerTLS.new()
	if _tls.connect_to_stream(_tcp, config["host"], options) != OK:
		return "Could not start TLS with the database."
	var deadline := Time.get_ticks_msec() + timeout_ms
	while _tls.get_status() == StreamPeerTLS.STATUS_HANDSHAKING and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		_tls.poll()
	if _tls.get_status() != StreamPeerTLS.STATUS_CONNECTED:
		if _tls.get_status() == StreamPeerTLS.STATUS_ERROR_HOSTNAME_MISMATCH:
			return "The database's TLS certificate doesn't match %s." % config["host"]
		return "The TLS handshake with the database failed (check sslmode and sslrootcert)."
	_tls.big_endian = true
	_stream = _tls
	return ""


func _login(config: Dictionary) -> String:
	var startup := StreamPeerBuffer.new()
	startup.big_endian = true
	startup.put_32(PROTOCOL_VERSION)
	for key in ["user", "database", "application_name", "client_encoding"]:
		var value: String = {
			"user": config["user"],
			"database": config["dbname"],
			"application_name": "multiplayer-survival-server",
			"client_encoding": "UTF8",
		}[key]
		_put_cstring(startup, key)
		_put_cstring(startup, value)
	startup.put_u8(0)
	var framed := StreamPeerBuffer.new()
	framed.big_endian = true
	framed.put_32(startup.data_array.size() + 4)
	framed.put_data(startup.data_array)
	if not _send(framed.data_array):
		return "Lost the connection to the database."

	var scram := {}
	while true:
		var message := _read_message()
		if message.is_empty():
			return "Lost the connection to the database while logging in."
		var body: StreamPeerBuffer = message["body"]
		match message["type"]:
			"E":
				return "The database refused the login: %s" % _error_fields(body)["M"]
			"R":
				var err := _authenticate(body, config, scram)
				if err != "":
					return err
			"Z":
				return ""
			_:
				pass  # ParameterStatus, BackendKeyData, notices
	return ""


func _authenticate(body: StreamPeerBuffer, config: Dictionary, scram: Dictionary) -> String:
	var password: String = config["password"]
	match body.get_32():
		0:  # AuthenticationOk
			return ""
		3:  # Cleartext password
			var reply := StreamPeerBuffer.new()
			_put_cstring(reply, password)
			return "" if _send(_message("p", reply.data_array)) else "Lost the connection to the database."
		5:  # MD5 password
			var salt := body.get_data(4)[1] as PackedByteArray
			var inner := _md5_hex((password + config["user"]).to_utf8_buffer())
			var outer_input := inner.to_utf8_buffer()
			outer_input.append_array(salt)
			var reply := StreamPeerBuffer.new()
			_put_cstring(reply, "md5" + _md5_hex(outer_input))
			return "" if _send(_message("p", reply.data_array)) else "Lost the connection to the database."
		10:  # SASL: pick SCRAM-SHA-256
			var mechanisms := []
			while body.get_available_bytes() > 1:
				mechanisms.append(_get_cstring(body))
			if not "SCRAM-SHA-256" in mechanisms:
				return "The database wants a login method this client doesn't support (%s)." % ", ".join(mechanisms)
			scram["nonce"] = Marshalls.raw_to_base64(_crypto.generate_random_bytes(18))
			var client_first_bare: String = "n=,r=" + scram["nonce"]
			scram["client_first_bare"] = client_first_bare
			var first := ("n,," + client_first_bare).to_utf8_buffer()
			var reply := StreamPeerBuffer.new()
			reply.big_endian = true
			_put_cstring(reply, "SCRAM-SHA-256")
			reply.put_32(first.size())
			reply.put_data(first)
			return "" if _send(_message("p", reply.data_array)) else "Lost the connection to the database."
		11:  # SASL continue: the server's first message
			var server_first := body.get_data(body.get_available_bytes())[1].get_string_from_utf8() as String
			var fields := _scram_fields(server_first)
			if not fields.get("r", "").begins_with(scram.get("nonce", "?")) or not fields.has("s") or not fields.has("i"):
				return "The database sent a bad SCRAM challenge."
			var salted := _pbkdf2_sha256(password.to_utf8_buffer(), Marshalls.base64_to_raw(fields["s"]), int(fields["i"]))
			var client_key := _crypto.hmac_digest(HashingContext.HASH_SHA256, salted, "Client Key".to_utf8_buffer())
			var stored_key := _sha256(client_key)
			var final_without_proof: String = "c=biws,r=" + fields["r"]
			var auth_message := "%s,%s,%s" % [scram["client_first_bare"], server_first, final_without_proof]
			var signature := _crypto.hmac_digest(HashingContext.HASH_SHA256, stored_key, auth_message.to_utf8_buffer())
			var proof := client_key.duplicate()
			for i in proof.size():
				proof[i] ^= signature[i]
			var server_key := _crypto.hmac_digest(HashingContext.HASH_SHA256, salted, "Server Key".to_utf8_buffer())
			scram["server_signature"] = Marshalls.raw_to_base64(
				_crypto.hmac_digest(HashingContext.HASH_SHA256, server_key, auth_message.to_utf8_buffer()))
			var reply := StreamPeerBuffer.new()
			reply.put_data((final_without_proof + ",p=" + Marshalls.raw_to_base64(proof)).to_utf8_buffer())
			return "" if _send(_message("p", reply.data_array)) else "Lost the connection to the database."
		12:  # SASL final: check the server knows the password too
			var server_final := body.get_data(body.get_available_bytes())[1].get_string_from_utf8() as String
			if _scram_fields(server_final).get("v", "") != scram.get("server_signature", ""):
				return "The database failed SCRAM server verification."
			return ""
		var code:
			return "The database wants an unsupported login method (%d)." % code


# --- Reading results -----------------------------------------------------------

func _collect(result: Dictionary) -> Dictionary:
	var columns := []
	while true:
		var message := _read_message()
		if message.is_empty():
			result["error"] = "Lost the connection to the database."
			result["connection_lost"] = true
			close()
			return result
		var body: StreamPeerBuffer = message["body"]
		match message["type"]:
			"T":
				columns.clear()
				for _i in body.get_u16():
					var column_name := _get_cstring(body)
					body.get_32()  # table oid
					body.get_16()  # column number
					var type_oid := body.get_32()
					body.get_data(8)  # size, modifier, format
					columns.append([column_name, type_oid])
			"D":
				var row := {}
				for i in body.get_u16():
					var length := body.get_32()
					var value: Variant = null
					if length >= 0:
						value = _convert(body.get_data(length)[1].get_string_from_utf8(), columns[i][1])
					row[columns[i][0]] = value
				result["rows"].append(row)
			"E":
				var fields := _error_fields(body)
				result["error"] = fields.get("M", "Unknown database error")
				result["code"] = fields.get("C", "")
			"Z":
				return result
			_:
				pass  # ParseComplete, BindComplete, CommandComplete, NoData, notices
	return result


func _convert(text: String, type_oid: int) -> Variant:
	match type_oid:
		OID_BOOL:
			return text == "t"
		OID_INT2, OID_INT4, OID_INT8:
			return int(text)
		OID_FLOAT4, OID_FLOAT8:
			return float(text)
	return text


func _error_fields(body: StreamPeerBuffer) -> Dictionary:
	var fields := {}
	while body.get_available_bytes() > 0:
		var code := body.get_u8()
		if code == 0:
			break
		fields[char(code)] = _get_cstring(body)
	return fields


# --- Framing -------------------------------------------------------------------

func _message(type: String, body: PackedByteArray) -> PackedByteArray:
	var framed := StreamPeerBuffer.new()
	framed.big_endian = true
	framed.put_u8(ord(type))
	framed.put_32(body.size() + 4)
	framed.put_data(body)
	return framed.data_array


func _send(bytes: PackedByteArray) -> bool:
	if _stream == null:
		return false
	return _stream.put_data(bytes) == OK


## { type: String, body: StreamPeerBuffer }, or {} if the connection dropped.
func _read_message() -> Dictionary:
	var header := _read_exact(5)
	if header.is_empty():
		return {}
	var length := (header[1] << 24) | (header[2] << 16) | (header[3] << 8) | header[4]
	var body := StreamPeerBuffer.new()
	body.big_endian = true
	if length > 4:
		var data := _read_exact(length - 4)
		if data.is_empty():
			return {}
		body.data_array = data
	return { "type": char(header[0]), "body": body }


func _read_exact(count: int) -> PackedByteArray:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while _inbox.size() < count:
		if _stream == null or Time.get_ticks_msec() > deadline:
			return PackedByteArray()
		if _tls != null:
			if _tls.get_status() == StreamPeerTLS.STATUS_CONNECTED:
				_tls.poll()
			if _tls.get_status() != StreamPeerTLS.STATUS_CONNECTED:
				return PackedByteArray()
		else:
			_tcp.poll()
			if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				return PackedByteArray()
		var available := _stream.get_available_bytes()
		if available > 0:
			var chunk := _stream.get_partial_data(available)
			if chunk[0] != OK:
				return PackedByteArray()
			_inbox.append_array(chunk[1])
		else:
			OS.delay_msec(1)
	var out := _inbox.slice(0, count)
	_inbox = _inbox.slice(count)
	return out


func _put_cstring(buffer: StreamPeerBuffer, text: String) -> void:
	buffer.put_data(text.to_utf8_buffer())
	buffer.put_u8(0)


func _get_cstring(buffer: StreamPeerBuffer) -> String:
	var bytes := PackedByteArray()
	while buffer.get_available_bytes() > 0:
		var b := buffer.get_u8()
		if b == 0:
			break
		bytes.append(b)
	return bytes.get_string_from_utf8()


# --- Hashing -------------------------------------------------------------------

func _scram_fields(message: String) -> Dictionary:
	var fields := {}
	for part in message.split(","):
		if part.length() >= 2 and part[1] == "=":
			fields[part[0]] = part.substr(2)
	return fields


func _pbkdf2_sha256(password: PackedByteArray, salt: PackedByteArray, iterations: int) -> PackedByteArray:
	var block := salt.duplicate()
	block.append_array(PackedByteArray([0, 0, 0, 1]))
	var u := _crypto.hmac_digest(HashingContext.HASH_SHA256, password, block)
	var result := u.duplicate()
	for _i in iterations - 1:
		u = _crypto.hmac_digest(HashingContext.HASH_SHA256, password, u)
		for j in result.size():
			result[j] ^= u[j]
	return result


func _sha256(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()


func _md5_hex(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(data)
	return ctx.finish().hex_encode()
