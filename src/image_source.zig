const std = @import("std");
const sdl3 = @import("sdl3");
const zip_lib = @import("zip.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;
const Texture = sdl3.render.Texture;
const Surface = sdl3.surface.Surface;
const Renderer = sdl3.render.Renderer;

pub const Source = union(enum) {
    directory: SourceDir,
    zip: *SourceZip,
    image: [:0]const u8,

    pub fn init(io: Io, allocator: Allocator, path: [:0]const u8) !@This() {
        const stat = try Io.Dir.cwd().statFile(io, path, .{});
        switch (stat.kind) {
            .file => {
                if (isImage(path)) return .{ .image = path };
                if (isZip(path)) return .{ .zip = try .init(io, allocator, path) };
            },
            .directory => return .{ .directory = try .init(io, allocator, path) },
            else => {},
        }

        return error.UnkownFileType;
    }

    pub fn deinit(self: *@This(), io: Io, allocator: Allocator) void {
        switch (self.*) {
            .directory => self.*.directory.deinit(allocator),
            .zip => |zip_src| {
                zip_src.deinit(io, allocator);
                allocator.destroy(zip_src);
            },
            else => {},
        }
    }

    pub fn getSurface(self: *@This(), allocator: Allocator, index: usize) !Surface {
        return try self.getData(Surface, allocator, index, null);
    }

    pub fn getTexture(self: *@This(), allocator: Allocator, index: usize, renderer: Renderer) !Texture {
        return try self.getData(Texture, allocator, index, renderer);
    }

    pub fn getData(self: *@This(), comptime T: type, allocator: Allocator, index: usize, renderer: ?Renderer) !T {
        const kind: enum { surface, texture } = comptime switch (T) {
            Texture => .texture,
            Surface => .surface,
            else => unreachable,
        };

        switch (self.*) {
            .image => |img_path| {
                return switch (kind) {
                    .surface => try sdl3.image.loadFile(img_path),
                    .texture => try sdl3.image.loadTexture(renderer.?, img_path),
                };
            },
            .directory => |dir_src| {
                const img_path = try dir_src.getImgPath(allocator, index);
                defer allocator.free(img_path);
                return switch (kind) {
                    .surface => try sdl3.image.loadFile(img_path),
                    .texture => try sdl3.image.loadTexture(renderer.?, img_path),
                };
            },
            .zip => |zip_src| {
                const data = try zip_src.getDataByIndex(allocator, index);
                defer allocator.free(data);
                const stream = try sdl3.io_stream.Stream.initFromConstMem(data);
                return switch (kind) {
                    .surface => try sdl3.image.loadIo(stream, true),
                    .texture => try sdl3.image.loadTextureIo(renderer.?, stream, true),
                };
            },
        }
    }
};

const SourceDir = struct {
    dir_path: [:0]const u8,
    sub_paths: [][:0]const u8,

    pub fn init(io: Io, allocator: Allocator, path: [:0]const u8) !@This() {
        const dir = try Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
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

        std.mem.sort([:0]const u8, paths.items, {}, sortDirEntryLt);
        return .{
            .dir_path = path,
            .sub_paths = try paths.toOwnedSlice(allocator),
        };
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        for (self.sub_paths) |sub_path| allocator.free(sub_path);
        allocator.free(self.sub_paths);
    }

    pub fn getImgPath(self: @This(), allocator: Allocator, index: usize) ![:0]const u8 {
        return try std.fs.path.joinZ(allocator, &.{ self.dir_path, self.sub_paths[index] });
    }
};

const ZipEntryInfo = struct {
    file_offset: u64,
    uncompressed_size: u64,
    filename: []const u8,
    compression_method: std.zip.CompressionMethod,
};

const SourceZip = struct {
    file: Io.File,
    buffer: [1024 * 4]u8 = undefined,
    reader: Io.File.Reader,
    entries: []const ZipEntryInfo,

    pub fn init(io: Io, allocator: Allocator, path: [:0]const u8) !*@This() {
        var zip_src = try allocator.create(SourceZip);
        errdefer allocator.destroy(zip_src);

        zip_src.file = try Io.Dir.cwd().openFile(io, path, .{});
        zip_src.reader = zip_src.file.reader(io, &zip_src.buffer);
        var entries = std.ArrayList(ZipEntryInfo).empty;
        errdefer entries.deinit(allocator);

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

            try entries.append(allocator, .{
                .file_offset = try zip_lib.getFileOffset(entry, stream),
                .uncompressed_size = entry.uncompressed_size,
                .compression_method = entry.compression_method,
                .filename = filename,
            });
        }

        std.mem.sort(ZipEntryInfo, entries.items, {}, sortZipEntryLt);
        zip_src.entries = try entries.toOwnedSlice(allocator);
        return zip_src;
    }

    pub fn deinit(self: *@This(), io: Io, allocator: Allocator) void {
        self.file.close(io);
        for (self.entries) |entry| allocator.free(entry.filename);
        allocator.free(self.entries);
    }

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

fn sortZipEntryLt(_: void, lhs: ZipEntryInfo, rhs: ZipEntryInfo) bool {
    return std.mem.order(u8, lhs.filename, rhs.filename) == .lt;
}

fn sortDirEntryLt(_: void, lhs: [:0]const u8, rhs: [:0]const u8) bool {
    return std.mem.orderZ(u8, lhs, rhs) == .lt;
}
