extends TestCase

const DIR := "user://test_run/container"
const FILE := DIR + "/c.sav"
var DATA := {"big": 9007199254740993, "v": Vector2i(-3, 7), "bytes": PackedByteArray([1, 2, 3]), "nested": {"a": [1, "x", 2.5]}}

var good: PackedByteArray


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	assert_eq(SaveContainer.write(FILE, {"save_version": 1}, DATA), OK)
	good = FileAccess.get_file_as_bytes(FILE)


func after_all() -> void:
	remove_dir_recursive(DIR)


func _read_with(bytes: PackedByteArray) -> SaveContainer.ReadResult:
	write_bytes(FILE, bytes)
	return SaveContainer.read(FILE)


func test_roundtrip_complex_values() -> void:
	var r := SaveContainer.read(FILE)
	assert_true(r.ok, r.error)
	assert_eq(r.data, DATA)
	assert_eq(r.header["save_version"], 1)


func test_header_only_read() -> void:
	var r := SaveContainer.read_header(FILE)
	assert_true(r.ok)
	assert_true(r.data.is_empty())
	assert_has(r.header, "payload_sha256")


func test_payload_bit_flip_detected() -> void:
	corrupt_byte(FILE, 3)
	var r := SaveContainer.read(FILE)
	assert_false(r.ok)
	assert_has(r.error, "payload checksum")


func test_header_bit_flip_detected() -> void:
	var b := good.duplicate()
	b[20] = b[20] ^ 0x01
	var r := _read_with(b)
	assert_false(r.ok)
	assert_has(r.error, "header checksum")


func test_truncation_and_trailing_garbage_detected() -> void:
	assert_has(_read_with(good.slice(0, good.size() - 10)).error, "size mismatch")
	assert_has(_read_with(good + PackedByteArray([0, 0, 0])).error, "size mismatch")


func test_bad_magic_empty_random_missing() -> void:
	var b := good.duplicate()
	b[0] = 0x58
	assert_eq(_read_with(b).error, "bad magic")
	assert_false(_read_with(PackedByteArray()).ok)
	var junk := PackedByteArray()
	junk.resize(5000)
	for i in junk.size():
		junk[i] = (i * 131 + 7) % 256
	assert_false(_read_with(junk).ok)
	assert_eq(SaveContainer.read(DIR + "/missing.sav").error, "file not found")


func test_non_dictionary_payload_rejected() -> void:
	# Build a structurally valid container whose payload is an Array.
	var raw := var_to_bytes([1, 2, 3])
	var payload := raw.compress(SaveContainer.COMPRESSION)
	var header := var_to_bytes({"payload_size": payload.size(), "raw_size": raw.size(), "payload_sha256": SaveContainer.sha256(payload)})
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	f.store_buffer(SaveContainer.MAGIC.to_ascii_buffer())
	f.store_32(SaveContainer.CONTAINER_VERSION)
	f.store_32(header.size())
	f.store_buffer(header)
	f.store_buffer(SaveContainer.sha256(header))
	f.store_buffer(payload)
	f.close()
	var r := SaveContainer.read(FILE)
	assert_false(r.ok)
	assert_has(r.error, "not a dictionary")
