fn main() {
    // 兼容两条构建链：
    //   - 旧路(setup.dart Build.buildHelper): 传入 TOKEN
    //   - 新路(plugins/setup/setup_hooks RustBuilder): 传入 CORE_SHA256
    // 二者语义相同(都是 core 可执行文件的 SHA256)，任一存在即可。
    let version = std::env::var("TOKEN")
        .or_else(|_| std::env::var("CORE_SHA256"))
        .unwrap_or_default();
    println!("cargo:rustc-env=TOKEN={}", version);
    println!("cargo:rerun-if-env-changed=TOKEN");
    println!("cargo:rerun-if-env-changed=CORE_SHA256");
}
