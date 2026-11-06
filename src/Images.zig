const std = @import("std");
const sdl3 = @import("sdl3");
const zip_lib = @import("zip.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;
const Texture = sdl3.render.Texture;
const Surface = sdl3.surface.Surface;
const Renderer = sdl3.render.Renderer;
const Sdl3Thread = sdl3.thread.Thread;

const Images = @This();

const ImageItem = struct {
    surface: ?Surface = null,
    texture: ?Texture = null,
};

const ImageItems = struct {
    previous: ?ImageItem = null,
    current: ?ImageItem = null,
    next: ?ImageItem = null,
};

const Source = union(enum) {
    directory: SourceDir,
    zip: *SourceZip,
    image: [:0]const u8,
};

const SourceDir = struct {
    dir_path: [:0]const u8,
    sub_paths: [][:0]const u8,
};

const SourceZip = struct {
    file: Io.File,
    buffer: [1024 * 4]u8 = undefined,
    reader: Io.File.Reader,
    entries: []const ZipEntryInfo,

    pub fn getDataByIndex(self: *SourceZip, allocator: Allocator, index: usize) ![]u8 {
        const entry = self.entries[index];
        try self.reader.seekTo(entry.file_offset);

        const reader = &self.reader.interface;
        switch (entry.compression_method) {
            .store => return try reader.readAllocAll(allocator, entry.uncompressed_size),
            .deflate => {
                var buffer: [std.compress.flate.max_window_len]u8 = undefined;
                var decompress: std.compress.flate.Decompress = .init(reader, .raw, &buffer);
                return try decompress.reader.readAllocAll(allocator, entry.uncompressed_size);
            },
            else => return error.Unsupported,
        }
    }
};

const ZipEntryInfo = struct {
    file_offset: u64,
    uncompressed_size: u64,
    filename: []const u8,
    compression_method: std.zip.CompressionMethod,
};

source: Source,
cursor: usize = 0,
items: ImageItems = .{},
mutex: Io.Mutex,
condition: Io.Condition,
active: bool = true,
ready: bool = true,

pub fn init(io: Io, allocator: Allocator, path: [:0]const u8) !@This() {
    const cwd = Io.Dir.cwd();
    const stat = try cwd.statFile(io, path, .{});
    const source: Source = sw: switch (stat.kind) {
        .file => {
            if (isImage(path)) break :sw .{ .image = path };
            if (!isZip(path)) return error.UnkownFileType;
            // TODO: sort by filename
            var zip_src = try allocator.create(SourceZip);
            errdefer allocator.destroy(zip_src);

            zip_src.file = try Io.Dir.cwd().openFile(io, path, .{});
            zip_src.reader = zip_src.file.reader(io, &zip_src.buffer);
            var entry_list = std.ArrayList(ZipEntryInfo).empty;
            errdefer entry_list.deinit(allocator);

            const stream = &zip_src.reader;
            var iterator = try std.zip.Iterator.init(stream);
            while (try iterator.next()) |entry| {
                if (entry.uncompressed_size == 0) continue;
                const name_buffer = try allocator.alloc(u8, entry.filename_len);
                const filename = try entry.getFilename(stream, name_buffer, .{});
                if (!isImage(filename)) {
                    allocator.free(name_buffer);
                    continue;
                }

                try entry_list.append(allocator, .{
                    .file_offset = try zip_lib.getFileOffset(entry, stream),
                    .uncompressed_size = entry.uncompressed_size,
                    .compression_method = entry.compression_method,
                    .filename = filename,
                });
            }

            zip_src.entries = try entry_list.toOwnedSlice(allocator);
            break :sw .{ .zip = zip_src };
        },
        .directory => {
            const dir = try cwd.openDir(io, path, .{ .iterate = true });
            defer dir.close(io);

            var dir_walker = try dir.walk(allocator);
            defer dir_walker.deinit();

            var paths = std.ArrayList([:0]const u8).empty;
            errdefer paths.deinit(allocator);

            while (try dir_walker.next(io)) |entry| {
                if (entry.kind == .directory) continue;
                if (!isImage(entry.basename)) continue;
                try paths.append(allocator, try allocator.dupeSentinel(u8, entry.path, 0));
            }

            // std.mem.sort([]const u8,paths.items,{},);
            break :sw .{
                .directory = .{
                    .dir_path = path,
                    .sub_paths = try paths.toOwnedSlice(allocator),
                },
            };
        },
        else => return error.UnkownFileType,
    };

    return .{
        .source = source,
        .mutex = .init,
        .condition = .init,
    };
}

pub fn deinit(self: *@This(), io: Io, allocator: Allocator) void {
    switch (self.source) {
        .directory => |dir_src| {
            for (dir_src.sub_paths) |sub_path| allocator.free(sub_path);
            allocator.free(dir_src.sub_paths);
        },
        .zip => |zip_src| {
            zip_src.file.close(io);
            for (zip_src.entries) |entry| allocator.free(entry.filename);
            allocator.free(zip_src.entries);
            allocator.destroy(zip_src);
        },
        else => {},
    }

    self.active = false;
    inline for (@typeInfo(ImageItems).@"struct".field_names) |field| {
        if (@field(self.items, field)) |item| {
            if (item.surface) |surface| surface.deinit();
            if (item.texture) |texture| texture.deinit();
        }
    }
}

pub fn next(self: *@This(), io: Io) !void {
    const items_length = switch (self.source) {
        .directory => |dir_src| dir_src.sub_paths.len,
        .zip => |zip_src| zip_src.entries.len,
        .image => return,
    };
    try self.mutex.lock(io);
    defer self.mutex.unlock(io);

    if (self.cursor == items_length - 1) return;
    self.cursor += 1;

    if (self.items.previous) |prev_item| {
        if (prev_item.surface) |surface| surface.deinit();
        if (prev_item.texture) |texture| texture.deinit();
    }
    self.items.previous = self.items.current;
    self.items.current = self.items.next;
    self.items.next = null;
    self.ready = true;
    self.condition.signal(io);
}

pub fn previous(self: *@This(), io: Io) !void {
    if (self.source == .image) return;
    try self.mutex.lock(io);
    defer self.mutex.unlock(io);

    if (self.cursor == 0) return;
    self.cursor -= 1;

    if (self.items.next) |next_item| {
        if (next_item.surface) |surface| surface.deinit();
        if (next_item.texture) |texture| texture.deinit();
    }
    self.items.next = self.items.current;
    self.items.current = self.items.previous;
    self.items.previous = null;
    self.ready = true;
    self.condition.signal(io);
}

pub fn getCurrentTexture(self: *@This(), io: Io, renderer: Renderer) !?Texture {
    try self.mutex.lock(io);
    defer self.mutex.unlock(io);

    const current = self.items.current orelse return null;
    if (current.texture) |texture| return texture;
    if (current.surface) |surface| {
        const texture = try renderer.createTextureFromSurface(surface);
        surface.deinit();
        self.items.current = .{ .texture = texture, .surface = null };
        return texture;
    }

    unreachable;
}

fn isImage(filename: []const u8) bool {
    const file_ext = std.fs.path.extension(filename);
    if (file_ext.len < 4) return false;
    inline for ([_][]const u8{ "jpg", "jpeg", "png", "gif", "webp", "avif" }) |ext| {
        if (std.mem.eql(u8, file_ext[1..], ext)) return true;
    }

    return false;
}

fn isZip(filename: []const u8) bool {
    const file_ext = std.fs.path.extension(filename);
    if (file_ext.len < 4) return false;
    inline for ([_][]const u8{ "zip", "cbz" }) |ext| {
        if (std.mem.eql(u8, file_ext[1..], ext)) return true;
    }

    return false;
}

pub fn loadAdjacentImages(io: Io, allocator: Allocator, images: *Images) !void {
    const src_length = switch (images.source) {
        .directory => |dir| dir.sub_paths.len,
        .zip => |zip| zip.entries.len,
        else => unreachable,
    };

    while (true) {
        try images.mutex.lock(io);
        defer images.mutex.unlock(io);
        if (!images.active) break;

        while (!images.ready) try images.condition.wait(io, &images.mutex);
        defer images.ready = false;
        std.debug.print("current: {d}\n", .{images.cursor});

        const prev_index = if (images.cursor > 0) images.cursor - 1 else 0;
        const next_index = images.cursor + 1;

        const should_load_next = next_index < src_length and (images.items.next == null or
            (images.items.next.?.texture == null and images.items.next.?.surface == null));

        const should_load_prev = images.cursor > 0 and prev_index >= 0 and (images.items.previous == null or
            (images.items.previous.?.texture == null and images.items.previous.?.surface == null));

        switch (images.source) {
            .directory => |dir_src| {
                if (should_load_next) {
                    const path = try std.fs.path.joinZ(allocator, &.{ dir_src.dir_path, dir_src.sub_paths[next_index] });
                    defer allocator.free(path);
                    images.items.next = .{ .surface = try sdl3.image.loadFile(path) };
                }

                if (should_load_prev) {
                    const path = try std.fs.path.joinZ(allocator, &.{ dir_src.dir_path, dir_src.sub_paths[prev_index] });
                    defer allocator.free(path);
                    images.items.previous = .{ .surface = try sdl3.image.loadFile(path) };
                }
                std.log.debug("next: {any} prev: {any}", .{ should_load_next, should_load_prev });
            },
            .zip => |zip_src| {
                if (should_load_next) {
                    const data = try zip_src.getDataByIndex(allocator, next_index);
                    defer allocator.free(data);
                    const stream = try sdl3.io_stream.Stream.initFromConstMem(data);
                    images.items.next = .{ .surface = try sdl3.image.loadIo(stream, true) };
                }

                if (should_load_prev) {
                    const data = try zip_src.getDataByIndex(allocator, prev_index);
                    defer allocator.free(data);
                    const stream = try sdl3.io_stream.Stream.initFromConstMem(data);
                    images.items.previous = .{ .surface = try sdl3.image.loadIo(stream, true) };
                }
            },
            else => {},
        }
    }
}
