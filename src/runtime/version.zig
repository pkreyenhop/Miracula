//! version.zig — build-injected version identity (`-Dversion`/`vdate`/`host`),
//! surfaced as runtime globals for the banner and the `%version` directive.

const options = @import("version_options");

/// `vdate`/`host` as NUL-terminated bytes (the C-string APIs need a sentinel).
const vdate_text = options.vdate ++ "\x00";
const host_text = options.host ++ "\x00";

/// The interpreter version number (the build option `-Dversion`).
pub const version: i32 = @as(i32, options.version);

/// The build date string, NUL-terminated for the C-string print path.
pub const vdate: [*:0]const u8 = vdate_text.ptr;

/// The build host string, NUL-terminated for the C-string print path.
pub const host: [*:0]const u8 = host_text.ptr;
