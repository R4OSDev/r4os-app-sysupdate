const r4os = @import("r4os");
const update_engine = @import("system_update_engine");
const retirement = @import("retire_update_center.zig");

pub fn r4_app_main(app: *r4os.App) i32 {
    if (retirement.dispatch(app)) |result| return result;
    return update_engine.runTerminal(app);
}
