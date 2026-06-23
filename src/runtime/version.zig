const options = @import("version_options");

const vdate_text = options.vdate ++ "\x00";
const host_text = options.host ++ "\x00";

pub var version: c_int = @as(c_int, options.version);
pub var vdate: [*:0]const u8 = vdate_text.ptr;
pub var host: [*:0]const u8 = host_text.ptr;
