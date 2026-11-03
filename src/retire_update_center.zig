//! Explicit, restartable retirement of the last standalone GUI. This is not
//! an update-engine migration: no update journal or server setting is changed.
const std = @import("std");
const r4os = @import("r4os");
const engine_api = @import("system_update_engine");
const inventory_api = r4os.system_update_inventory;
const gui = "C:\\R4OS\\SOFTWARE\\DESKTOP\\UPDATE.R4X";
const saved = "C:\\R4OS\\SOFTWARE\\DESKTOP\\UPDATE.OLD";
const catalog = "C:\\R4OS\\CONFIG\\MODULES.JSON";
const staged = "C:\\R4OS\\CONFIG\\UPDRET.NEW";
const backup = "C:\\R4OS\\CONFIG\\UPDRET.BAK";
const lock = "C:\\R4OS\\UPDATE\\STAGED\\SYSLOCK.LCK";
const original_sha = "4191707700767d626701ed570ac8555c924c9c464df7b9a5ea9784050918533d";
var input: [inventory_api.max_bytes]u8 = undefined;
var output: [inventory_api.max_bytes]u8 = undefined;
var inventory: inventory_api.Inventory = undefined;
var chunk: [65536]u8 = undefined;

pub fn dispatch(app: *r4os.App) ?i32 {
    const sys = app.system();
    const args = std.mem.trim(u8, std.mem.span(sys.argsRaw()), " \t\r\n");
    var parts = std.mem.tokenizeAny(u8, args, " \t");
    if (!std.ascii.eqlIgnoreCase(parts.next() orelse "", "RETIRE-UPDATE-CENTER")) {
        if (args.len == 0 or std.ascii.eqlIgnoreCase(args, "/?") or std.ascii.eqlIgnoreCase(args, "--help"))
            sys.println("SYSUPD RETIRE-UPDATE-CENTER [/CHECK] - archive the retired 0.2.8 GUI; close UPDATE and stop UPDSVC first.");
        return null;
    }
    const option = parts.next();
    const check = if (option) |value| std.ascii.eqlIgnoreCase(value, "/CHECK") else false;
    if ((option != null and !check) or parts.next() != null) return failure(&sys, "arguments");
    run(app, check) catch |err| return failure(&sys, @errorName(err));
    return 0;
}

fn failure(sys: *const r4os.r4sys.Context, reason: []const u8) i32 {
    sys.write("SYSUPD RETIRE-UPDATE-CENTER result: FAILED reason=");
    sys.println(reason);
    return 1;
}

fn info(sys: *const r4os.r4sys.Context, path: [*:0]const u8) !?r4os.abi.FileInfo {
    var result: r4os.abi.FileInfo = .{};
    const rc = sys.fileInfoRaw(path, &result);
    if (rc < 0) return error.LookupIo;
    return if (rc > 0 and result.exists != 0) result else null;
}

fn exactGui(sys: *const r4os.r4sys.Context, path: [*:0]const u8) !bool {
    const value = try info(sys, path) orelse return false;
    if (value.is_dir != 0 or value.size != 1543877) return error.UnknownGuiPreserved;
    var sha = std.crypto.hash.sha2.Sha256.init(.{});
    var offset: u32 = 0;
    while (offset < value.size) {
        const length: usize = @intCast(@min(chunk.len, value.size - offset));
        if (sys.fileReadAt(path, offset, chunk[0..length]) != length) return error.GuiRead;
        sha.update(chunk[0..length]);
        offset += @intCast(length);
    }
    var digest: [32]u8 = undefined;
    sha.final(&digest);
    if (!std.mem.eql(u8, &std.fmt.bytesToHex(digest, .lower), original_sha)) return error.UnknownGuiPreserved;
    return true;
}

fn quiescent(engine: *engine_api.Engine) !void {
    const state = engine.status();
    if (state.exit_code != 0 or !switch (state.state) {
        .idle, .installed, .rolled_back => true,
        else => false,
    }) return error.UpdatePending;
}

fn run(app: *r4os.App, check: bool) !void {
    const sys = app.system();
    // No stop, kill or autostart mutation is hidden in this command.
    for ([_][*:0]const u8{ gui, "C:\\R4OS\\SERVICES\\UPDSVC.R4X" }) |path| {
        if (sys.programModuleRunning(path) != 0) return error.StopGuiAndUpdsvc;
    }
    var engine = engine_api.Engine.init(app);
    try quiescent(&engine);
    if (sys.fileStreamBegin(lock, r4os.abi.file_stream_open_create | r4os.r4sys.file_stream_open_lease) != 0) return error.UpdateLeaseBusy;
    defer _ = sys.fileStreamAbort(lock);
    const lock_body = "SYSUPD_LOCK=1\n";
    if (sys.fileStreamWrite(lock, 0, lock_body, 0) != lock_body.len or
        sys.fileStreamFinish(lock, lock_body.len, r4os.r4sys.file_stream_finish_keep_ownership) != 0) return error.UpdateLeaseIo;
    try quiescent(&engine);
    const file = try info(&sys, catalog) orelse return error.InventoryMissing;
    if (file.is_dir != 0 or file.size == 0 or file.size > input.len) return error.InventorySize;
    const bytes = input[0..@intCast(file.size)];
    if (sys.fileRead(catalog, bytes) != bytes.len or !inventory_api.Inventory.parse(bytes, &inventory)) return error.InventoryInvalid;
    var row = false;
    var desktop = false;
    for (inventory.entries[0..inventory.count]) |entry| {
        if (r4os.r4u_manifest.targetEquals(entry.target, "/R4OS/SOFTWARE/DESKTOP/UPDATE.R4X")) {
            if (entry.kind != .r4x or !std.ascii.eqlIgnoreCase(entry.name, "UPDATE") or !std.mem.eql(u8, entry.version, "0.2.8")) return error.UnknownInventoryPreserved;
            row = true;
        }
        if (entry.kind == .r4x and std.ascii.eqlIgnoreCase(entry.name, "R4DESK")) {
            const version = std.SemanticVersion.parse(entry.version) catch return error.DesktopVersion;
            desktop = version.order(.{ .major = 0, .minor = 1, .patch = 201 }) != .lt;
        }
    }
    if (!desktop) return error.InstallDesktop201First;
    const active = try exactGui(&sys, gui);
    const archived = try exactGui(&sys, saved);
    if (!active and !row) {
        sys.println("SYSUPD RETIRE-UPDATE-CENTER result: OK already-retired");
        return;
    }
    if (active and archived) return error.ArchiveConflict;
    if (row and !active and !archived) return error.GuiOriginalMissing;
    const rendered = if (row) result: {
        if (!inventory.removeExact(.r4x, "UPDATE", "/R4OS/SOFTWARE/DESKTOP/UPDATE.R4X")) return error.InventoryConflict;
        break :result inventory.render(&output) orelse return error.InventoryRender;
    } else "";
    if (try info(&sys, backup) != null) return error.InventoryBackupConflict;
    // A prior private stage is accepted only if it is exactly this transition.
    if (try info(&sys, staged)) |old| {
        if (old.is_dir != 0 or old.size != rendered.len or sys.fileRead(staged, &chunk) != rendered.len or
            !std.mem.eql(u8, chunk[0..rendered.len], rendered)) return error.InventoryStageConflict;
    }
    if (check) {
        sys.println("SYSUPD RETIRE-UPDATE-CENTER result: OK check-only");
        return;
    }
    // The readback settles an ambiguous rename completion without a second
    // rename or replacement: only the known bytes at the archive count.
    if (active) _ = sys.fileRename(gui, saved);
    if (!try exactGui(&sys, saved) or try info(&sys, gui) != null) return error.GuiArchiveReadback;
    if (row) {
        if (try info(&sys, staged) == null) {
            if (sys.fileStreamBegin(staged, r4os.abi.file_stream_open_create) != 0) return error.InventoryStage;
            var complete = false;
            defer if (!complete) {
                _ = sys.fileStreamAbort(staged);
            };
            if (sys.fileStreamWrite(staged, 0, rendered, 0) != rendered.len or sys.fileStreamFinish(staged, rendered.len, 0) != 0) return error.InventoryStage;
            complete = true;
        }
        if (sys.fileReplaceAtomic(catalog, staged, backup, r4os.r4sys.file_replace_atomic_flag_consume_stage) != 0) return error.InventoryCommit;
        if (sys.fileRead(catalog, &input) != rendered.len or !std.mem.eql(u8, input[0..rendered.len], rendered)) return error.InventoryReadback;
    }
    sys.println("SYSUPD RETIRE-UPDATE-CENTER result: OK GUI archived; inventory retired; backend and update journals unchanged");
}
