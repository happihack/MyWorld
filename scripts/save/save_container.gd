class_name SaveContainer
extends RefCounted
## Self-verifying save file format (bible §31.9, D-07).
##
## Layout:
##   "WIAB"                      4 bytes magic
##   container_version           u32 (layout of this file, not of the game data)
##   header_size                 u32
##   header                      var_to_bytes(Dictionary) — readable without
##                               touching the payload (world lists, backups)
##   header_sha256               32 bytes
##   payload                     ZSTD-compressed var_to_bytes(Dictionary)
##
## The header records payload size, uncompressed size and payload SHA-256, so
## every kind of corruption (bad magic, truncation, bit flips in either part,
## wrong types) is detected before any game data is used. Objects are never
## encoded or decoded (var_to_bytes/bytes_to_var without objects).

const MAGIC := "WIAB"
const CONTAINER_VERSION := 1
const HASH_SIZE := 32
const MAX_HEADER_SIZE := 64 * 1024
const COMPRESSION := FileAccess.COMPRESSION_ZSTD


class ReadResult:
	extends RefCounted
	var ok := false
	var error := ""
	var header: Dictionary = {}
	var data: Dictionary = {}


## Writes `data` with caller-supplied header fields (e.g. save_version, world_id).
## The integrity fields are added automatically.
static func write(path: String, header_fields: Dictionary, data: Dictionary) -> Error:
	return write_raw(path, header_fields, var_to_bytes(data))


## The same, from `data` already turned into bytes (var_to_bytes) — what a
## save on a worker thread is given (M22: the world is read on the main thread,
## compressed, hashed and written on another). Safe on any thread.
static func write_raw(path: String, header_fields: Dictionary, raw: PackedByteArray) -> Error:
	var payload := raw.compress(COMPRESSION)
	var header := header_fields.duplicate()
	header["payload_size"] = payload.size()
	header["raw_size"] = raw.size()
	header["payload_sha256"] = sha256(payload)
	var header_bytes := var_to_bytes(header)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(MAGIC.to_ascii_buffer())
	file.store_32(CONTAINER_VERSION)
	file.store_32(header_bytes.size())
	file.store_buffer(header_bytes)
	file.store_buffer(sha256(header_bytes))
	file.store_buffer(payload)
	var err := file.get_error()
	file.close()
	return err


## Reads and fully verifies a container. Never crashes on bad input.
static func read(path: String) -> ReadResult:
	var result := ReadResult.new()
	var parsed := _read_header(path)
	if not parsed.ok:
		return parsed
	result.header = parsed.header
	var bytes := FileAccess.get_file_as_bytes(path)
	var payload_start: int = parsed.data["payload_start"]
	var payload_size := int(result.header.get("payload_size", -1))
	var raw_size := int(result.header.get("raw_size", -1))
	if payload_size < 0 or raw_size < 0 or bytes.size() != payload_start + payload_size:
		return _fail(result, "payload size mismatch (file %d, expected %d)" % [bytes.size(), payload_start + payload_size])
	var payload := bytes.slice(payload_start)
	if sha256(payload) != result.header.get("payload_sha256", PackedByteArray()):
		return _fail(result, "payload checksum mismatch")
	var raw := payload.decompress(raw_size, COMPRESSION)
	if raw.size() != raw_size:
		return _fail(result, "payload decompression failed")
	var value: Variant = bytes_to_var(raw)
	if typeof(value) != TYPE_DICTIONARY:
		return _fail(result, "payload is not a dictionary")
	result.data = value
	result.ok = true
	return result


## Reads and verifies only the header (cheap; no payload checksum).
static func read_header(path: String) -> ReadResult:
	var parsed := _read_header(path)
	parsed.data = {}
	return parsed


static func sha256(bytes: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish()


static func _read_header(path: String) -> ReadResult:
	var result := ReadResult.new()
	if not FileAccess.file_exists(path):
		return _fail(result, "file not found")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail(result, "cannot open (%s)" % error_string(FileAccess.get_open_error()))
	var length := file.get_length()
	if length < 12:
		return _fail(result, "file too short")
	if file.get_buffer(4).get_string_from_ascii() != MAGIC:
		return _fail(result, "bad magic")
	var container_version := file.get_32()
	if container_version != CONTAINER_VERSION:
		return _fail(result, "unsupported container version %d" % container_version)
	var header_size := file.get_32()
	if header_size <= 0 or header_size > MAX_HEADER_SIZE or 12 + header_size + HASH_SIZE > length:
		return _fail(result, "bad header size %d" % header_size)
	var header_bytes := file.get_buffer(header_size)
	var header_hash := file.get_buffer(HASH_SIZE)
	if sha256(header_bytes) != header_hash:
		return _fail(result, "header checksum mismatch")
	var header: Variant = bytes_to_var(header_bytes)
	if typeof(header) != TYPE_DICTIONARY:
		return _fail(result, "header is not a dictionary")
	result.header = header
	result.data = {"payload_start": 12 + header_size + HASH_SIZE}
	result.ok = true
	return result


static func _fail(result: ReadResult, message: String) -> ReadResult:
	result.ok = false
	result.error = message
	return result
