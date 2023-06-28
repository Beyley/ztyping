const std = @import("std");
const builtin = @import("builtin");

const Context = extern struct {
    context: ?*anyopaque,

    ///Converts the original array into the format specified by the context
    pub fn convert(self: Context, allocator: std.mem.Allocator, original: []u8) ![]u8 {
        //Allocate a destination slicethat is 1.5x the size of the original slice
        var dest_line = try allocator.alloc(u8, original.len + (original.len / 2));
        defer allocator.free(dest_line);

        var orig_c_ptr: [*c]u8 = original.ptr;
        var dst_c_ptr: [*c]u8 = dest_line.ptr;
        var orig_bytes_left = original.len;
        var dest_bytes_left = dest_line.len;

        while (orig_bytes_left > 0) {
            //Convert as much of the data as we can
            var ret = ziconv_convert(self, &orig_c_ptr, &dst_c_ptr, &orig_bytes_left, &dest_bytes_left);
            if (ret == @as(usize, @bitCast(@as(isize, -1)))) {
                var errno = std.c._errno().*;

                //errno 7 = E2BIG
                if (errno != 7) {
                    return error.UnableToConvertShiftJISToUTF8;
                }
            }

            //If theres still more source bytes, and the destination is full
            if (orig_bytes_left > 0 and dest_bytes_left == 0) {
                //Allocate a new bigger array
                var new = try allocator.alloc(u8, dest_line.len + orig_bytes_left * 2);
                //Copy the old data into the new array
                @memcpy(new[0..dest_line.len], dest_line);

                //Mark that we have more space now
                dest_bytes_left += new.len - dest_line.len;

                //Free the old destination array
                allocator.free(dest_line);

                //Set the old destination array to the new one
                dest_line = new;

                //Update the destination C ptr
                dst_c_ptr = dest_line.ptr;
            }
        }

        //Return a copy of the destination array
        return try allocator.dupe(u8, dest_line[0 .. dest_line.len - dest_bytes_left]);
    }
};

pub extern fn ziconv_open(src: [*c]const u8, dst: [*c]const u8) Context;
pub extern fn ziconv_close(context: Context) void;
extern fn ziconv_convert(context: Context, src: [*c][*c]u8, dst: [*c][*c]u8, src_len: *usize, dst_len: *usize) usize;
