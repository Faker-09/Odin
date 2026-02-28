package test_core_bytes

import "core:bytes"
import "core:slice"
import "core:testing"

@private SIMD_SCAN_WIDTH :: 8 * size_of(uintptr)

@test
test_index_byte_sanity :: proc(t: ^testing.T) {
	// We must be able to find the byte at the correct index.
	data := make([]u8, 2 * SIMD_SCAN_WIDTH)
	defer delete(data)
	slice.fill(data, '-')

	INDEX_MAX :: SIMD_SCAN_WIDTH - 1

	for offset in 0..<INDEX_MAX {
		for idx in 0..<INDEX_MAX {
			sub := data[offset:]
			sub[idx] = 'o'
			if !testing.expect_value(t, bytes.index_byte(sub, 'o'), idx) {
				return
			}
			if !testing.expect_value(t, bytes.last_index_byte(sub, 'o'), idx) {
				return
			}
			sub[idx] = '-'
		}
	}
}

@test
test_index_byte_empty :: proc(t: ^testing.T) {
	a: [1]u8
	testing.expect_value(t, bytes.index_byte(a[0:0], 'o'), -1)
	testing.expect_value(t, bytes.last_index_byte(a[0:0], 'o'), -1)
}

@test
test_index_byte_multiple_hits :: proc(t: ^testing.T) {
	for n in 5..<256 {
		data := make([]u8, n)
		defer delete(data)
		slice.fill(data, '-')

		data[n-1] = 'o'
		data[n-3] = 'o'
		data[n-5] = 'o'

		// Find the first one.
		if !testing.expect_value(t, bytes.index_byte(data, 'o'), n-5) {
			return
		}

		// Find the last one.
		if !testing.expect_value(t, bytes.last_index_byte(data, 'o'), n-1) {
			return
		}
	}
}

@test
test_index_byte_zero :: proc(t: ^testing.T) {
	// This test protects against false positives in uninitialized memory.
	for n in 1..<256 {
		data := make([]u8, n + 64)
		defer delete(data)
		slice.fill(data, '-')

		// Positive hit.
		data[n-1] = 0
		if !testing.expect_value(t, bytes.index_byte(data[:n], 0), n-1) {
			return
		}
		if !testing.expect_value(t, bytes.last_index_byte(data[:n], 0), n-1) {
			return
		}

		// Test for false positives.
		data[n-1] = '-'
		if !testing.expect_value(t, bytes.index_byte(data[:n], 0), -1) {
			return
		}
		if !testing.expect_value(t, bytes.last_index_byte(data[:n], 0), -1) {
			return
		}
	}
}

@test
test_last_index_byte_bounds :: proc(t: ^testing.T) {
	input := "helloworld.odin."
	assert(len(input) == 16)
	idx := bytes.last_index_byte(transmute([]byte)(input[:len(input)-1]), '.')
	testing.expect_value(t, idx, 10)
}

utf8_test_strings :: struct {comment, input, output: string, valid: bool}

scrub_test_strings := []utf8_test_strings {
	{"Single valid ASCII char", "~", "~", true},
	{"Invalid single byte", "\xF8", "🌺", false},
	{"Valid 2 Octet Sequence", "\xc3\xb1", "\xc3\xb1", true},
	{"Invalid 2 Octet Sequence", "\xc3\x28", "🌺(", false},
	{"Invalid Sequence Identifier", "\xa0\xa1", "🌺", false},
	{"Valid 3 Octet sequence X 2,", "\xe2\x82\xac \xe2\x80\xa6", "€ …", true},
	{"Invalid 3 Octet Sequence (in 2nd Octet)", "\xe2\x28\xa1", "🌺(🌺", false},
	{"Invalid 3 Octet Sequence (in 3rd Octet)", "\xe2\x82\x28", "🌺(", false},
	{"Valid 4 Octet Sequence", "\xf0\x90\x8c\xbc", "𐌼", true},
	{"Valid 3 Octet Sequence X 3 with a bad byte", "小猫\xa9咪", "小猫🌺咪", false},
	{"Invalid 4 Octet Sequence (in 2nd Octet)", "\xf0\x28\x8c\xbc", "🌺(🌺", false},
	{"Invalid 4 Octet Sequence (in 3rd Octet)", "\xf0\x90\x28\xbc", "🌺(🌺", false},
	{"Invalid 4 Octet Sequence (in 4th Octet)", "\xf0\x90\x8c\x28", "🌺(", false},
	{"Valid 5 Octet Sequence (but not Unicode)", "\xf8\xa1\xa1\xa1\xa1", "🌺", false},
	{"Valid 6 Octet Sequence (but not Unicode)", "\xfc\xa1\xa1\xa1\xa1\xa1", "🌺", false},
	{"Valid emoji, 10 Owls", "🦉🦉🦉🦉🦉🦉🦉🦉🦉🦉", "🦉🦉🦉🦉🦉🦉🦉🦉🦉🦉", true},
	{"Emoji with Zero-Width Joiners", "\U0001F468\U0000200D\U0001F469\U0000200D\U0001F467", "👨‍👩‍👧", true},
	{"Valid emoji", "\xF0\x9f\xa6\x88\xF0\x9F\xA5\xBD\xF0\x9F\xA5\xB1🦉", "🦈🥽🥱🦉", true},
	{"Valid emoji, invalid 2 Octet seq", "🦈\xc3\xc4 Tears:\xF0\x9F\x98\x82 \"Hello, 世界\"🦉", "🦈🌺 Tears:😂 \"Hello, 世界\"🦉", false},
	{"Invalid, Valid, Invalid, Valid, Invalid", "\xc3\xc4 \xe2\x82\xac \xc3\xc4 \xe2\x80\xa6 \xc3\xc4", "🌺 € 🌺 … 🌺", false},
	{"Invalid", "\xF9\xFA\xFE\xFF\xC0\xC1\xF5\xF6\xF7\xF8\xF9\xFA\xFE\xFF\xC0\xC1", "🌺", false},
}

@test
test_scrub_invalid_utf8 :: proc(t: ^testing.T) {
	flower := "🌺"
	replacement := transmute([]u8)flower

	for b in scrub_test_strings {
		input := transmute([]u8)b.input

		{
			// For testing the original scrub
			scrubbed := bytes.scrub(input, replacement)
			defer delete(scrubbed)
			output := string(scrubbed)
			testing.expect_value(t, output, b.output)
		}

when false {

		// For testing the new scrub
		{
			scrubbed, valid := bytes.scrub(input, replacement)
			defer delete(scrubbed)
			testing.expectf(t, valid == b.valid, "expected %v", b.valid)
			output := string(scrubbed)
			testing.expect_value(t, output, b.output)
		}

		{
			// Test copy only if needed
			scrubbed, valid := bytes.scrub(input, replacement, false)
			output := string(scrubbed)
			if b.valid {
				// Get a mem leak if this is broken and has allocated
				testing.expect_value(t, output, "")
			} else {
				testing.expect_value(t, output, b.output)
				delete(scrubbed)
			}
		}

}  // when


	}
}
