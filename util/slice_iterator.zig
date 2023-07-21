pub fn SliceIterator(comptime T: type) type {
    return struct {
        items: []const T,
        idx: usize,

        const Self = @This();

        pub fn new(items: []const T) Self {
            return .{
                .items = items,
                .idx = 0,
            };
        }

        pub fn next(self: *Self) ?T {
            if (self.idx == self.items.len) return null;

            self.idx += 1;

            return self.items[self.idx - 1];
        }
    };
}
