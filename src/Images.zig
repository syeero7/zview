const std = @import("std");
const sdl3 = @import("sdl3");

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
    zip: SourceZip,
    image: [:0]const u8,
};

const SourceDir = struct {
    dir_path: [:0]const u8,
    sub_paths: [][:0]const u8,
};

const SourceZip = struct {
    filenames: [][]const u8,
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
            return error.UnkownFileType;
            // if (!isZip(file_ext)) return error.UnkownFileType;
            //
            // // TODO: lazy load images
            // // TODO: sort by filename
            // const file = try Io.Dir.cwd().openFile(io, path, .{});
            // defer file.close(io);
            // var buffer: [1024 * 4]u8 = undefined;
            // var file_reader = file.reader(io, &buffer);
            //
            // var alloc_writer = Io.Writer.Allocating.init(allocator);
            // defer alloc_writer.deinit();
            // var iterator = try std.zip.Iterator.init(&file_reader);
            // while (try iterator.next()) |entry| {
            //     if (entry.uncompressed_size == 0) continue;
            //     const name_buf = try allocator.alloc(u8, entry.filename_len);
            //     defer allocator.free(name_buf);
            //
            //     const file_name = try entry.getFilename(&file_reader, name_buf, .{});
            //     if (!isImage(std.fs.path.extension(file_name))) continue;
            //
            //     defer alloc_writer.clearRetainingCapacity();
            //     try alloc_writer.ensureTotalCapacity(entry.uncompressed_size);
            //     try entry.extractTo(&file_reader, &alloc_writer.writer);
            //
            //     const stream = try sdl3.io_stream.Stream.initFromConstMem(alloc_writer.written());
            //     try texture_list.append(allocator, try sdl3.image.loadTextureIo(renderer, stream, true));
            // }
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

            const items = try paths.toOwnedSlice(allocator);
            std.debug.print("{s}\n", .{items[0]});
            // std.mem.sort([]const u8,paths.items,{},);
            break :sw .{
                .directory = .{
                    .dir_path = path,
                    .sub_paths = items,
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

pub fn deinit(self: *@This(), allocator: Allocator) void {
    switch (self.source) {
        .directory => |dir_src| allocator.free(dir_src.sub_paths),
        .zip => |zip_src| allocator.free(zip_src.filenames),
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
        .zip => |zip_src| zip_src.filenames.len,
        .image => return,
    };

    try self.mutex.lock(io);
    defer self.mutex.unlock(io);

    self.cursor = @min(items_length - 1, self.cursor + 1);
    if (self.cursor == items_length - 1) return;
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

    self.cursor = if (self.cursor == 0) 0 else self.cursor - 1;
    if (self.cursor == 0) return;
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

pub fn getCurrentTexture(self: *@This(), io: Io, renderer: Renderer) !Texture {
    try self.mutex.lock(io);
    defer self.mutex.unlock(io);
    var current = self.items.current.?;
    if (current.texture) |texture| return texture;
    if (current.surface) |surface| {
        current.texture = try renderer.createTextureFromSurface(surface);
        surface.deinit();
        return current.texture.?;
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

pub fn loadAdjacentImages(io_ptr: *const Io, allocator_ptr: *const Allocator, images: *Images) !void {
    const io = io_ptr.*;
    const allocator = allocator_ptr.*;

    try images.mutex.lock(io);
    const src_length = switch (images.source) {
        .directory => |dir| dir.sub_paths.len,
        .zip => |zip| zip.filenames.len,
        else => 1,
    };
    images.mutex.unlock(io);

    while (true) {
        try images.mutex.lock(io);
        defer images.mutex.unlock(io);
        if (!images.active) break;

        while (!images.ready) {
            try images.condition.wait(io, &images.mutex);
        }
        defer images.ready = false;

        const prev_index = images.cursor - 1;
        const next_index = images.cursor + 1;

        const should_load_next = next_index < src_length and (images.items.next == null or
            (images.items.next.?.texture == null and images.items.next.?.surface == null));

        const should_load_prev = prev_index > 0 and (images.items.previous == null or
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
                _ = zip_src;
            },
            else => {},
        }
    }
}
