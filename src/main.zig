const r4os = @import("r4os");
const update_engine = @import("system_update_engine");

pub fn r4_app_main(app: *r4os.App) i32 {
    return update_engine.runTerminal(app);
}
