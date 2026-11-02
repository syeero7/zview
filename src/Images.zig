const std = @import("std");
const sdl3 = @import("sdl3");

const Io = std.Io;
const Allocator = std.mem.Allocator;
const Texture = sdl3.render.Texture;
const Renderer = sdl3.render.Renderer;

const Images = @This();

cursor: usize = 0,
textures: []Texture,

pub fn init(io: Io, allocator: Allocator, renderer: Renderer, path: [:0]const u8) !@This() {
    var texture_list = std.ArrayList(Texture).empty;
    errdefer texture_list.deinit(allocator);

    const cwd = Io.Dir.cwd();
    const stat = try cwd.statFile(io, path, .{});
    sw: switch (stat.kind) {
        .file => {
            const file_ext = std.fs.path.extension(path);
            if (isImage(file_ext)) {
                try texture_list.append(allocator, try sdl3.image.loadTexture(renderer, path));
                break :sw;
            }

            if (!isZip(file_ext)) return error.UnkownFileType;
            // TODO: lazy load images
            // TODO: sort by filename
            const file = try Io.Dir.cwd().openFile(io, path, .{});
            defer file.close(io);
            var buffer: [1024 * 4]u8 = undefined;
            var file_reader = file.reader(io, &buffer);

            var alloc_writer = Io.Writer.Allocating.init(allocator);
            defer alloc_writer.deinit();
            var iterator = try std.zip.Iterator.init(&file_reader);
            while (try iterator.next()) |entry| {
                if (entry.uncompressed_size == 0) continue;
                const name_buf = try allocator.alloc(u8, entry.filename_len);
                defer allocator.free(name_buf);

                const file_name = try entry.getFilename(&file_reader, name_buf, .{});
                if (!isImage(std.fs.path.extension(file_name))) continue;

                defer alloc_writer.clearRetainingCapacity();
                try alloc_writer.ensureTotalCapacity(entry.uncompressed_size);
                try entry.extractTo(&file_reader, &alloc_writer.writer);
                const stream = try sdl3.io_stream.Stream.initFromConstMem(alloc_writer.written());
                try texture_list.append(allocator, try sdl3.image.loadTextureIo(renderer, stream, true));
            }
        },
        .directory => {
            // TODO: load textures asynchronously
            const dir = try cwd.openDir(io, path, .{ .iterate = true });
            defer dir.close(io);

            var dir_walker = try dir.walk(allocator);
            defer dir_walker.deinit();
            while (try dir_walker.next(io)) |entry| {
                if (entry.kind == .directory) continue;
                const file_ext = std.fs.path.extension(entry.basename);
                if (!isImage(file_ext)) continue;

                const entry_path = try std.fs.path.joinZ(allocator, &.{ path, entry.basename });
                defer allocator.free(entry_path);
                try texture_list.append(allocator, try sdl3.image.loadTexture(renderer, entry_path));
            }
        },
        else => return error.UnkownFileType,
    }

    if (texture_list.items.len == 0) return error.NoTextures;
    return .{ .textures = try texture_list.toOwnedSlice(allocator) };
}

pub fn deinit(self: *@This(), allocator: Allocator) void {
    for (self.textures) |texture| {
        texture.deinit();
    }

    allocator.free(self.textures);
    self.textures = undefined;
}

pub fn next(self: *@This()) void {
    self.cursor = @min(self.textures.len - 1, self.cursor + 1);
}

pub fn previous(self: *@This()) void {
    self.cursor = if (self.cursor == 0) 0 else self.cursor - 1;
}

pub fn getCurrentTexture(self: *@This()) Texture {
    return self.textures[self.cursor];
}

fn isImage(file_ext: []const u8) bool {
    if (file_ext.len < 4) return false;
    inline for ([_][]const u8{ "jpg", "jpeg", "png", "gif", "webp", "avif" }) |img_ext| {
        if (std.mem.eql(u8, file_ext[1..], img_ext)) return true;
    }

    return false;
}

fn isZip(file_ext: []const u8) bool {
    if (file_ext.len < 4) return false;
    inline for ([_][]const u8{ "zip", "cbz" }) |ext| {
        if (std.mem.eql(u8, file_ext[1..], ext)) return true;
    }

    return false;
}
