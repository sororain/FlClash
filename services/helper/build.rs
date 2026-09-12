fn main() {
    // core 可执行文件名与 SHA256 都要在编译期注入 helper（`env!`），由构建链给出；
    // 缺省时给默认值，让 helper 至少能编译通过（运行时再拒绝服务）。
    //
    // 两条构建链：
    //   - setup.dart Build.buildHelper（旧内联路，仍传 TOKEN）
    //   - plugins/setup/setup_hooks RustBuilder（构建钩子路，传 CORE_SHA256/CORE_NAME）
    // TOKEN 与 CORE_SHA256 语义相同(都是 core 可执行文件的 SHA256)，任一存在即可。
    let core_sha256 = std::env::var("CORE_SHA256")
        .or_else(|_| std::env::var("TOKEN"))
        .unwrap_or_default();
    let core_name =
        std::env::var("CORE_NAME").unwrap_or_else(|_| "SororainCore.exe".to_string());

    println!("cargo:rustc-env=CORE_SHA256={}", core_sha256);
    println!("cargo:rustc-env=CORE_NAME={}", core_name);
    println!("cargo:rerun-if-env-changed=CORE_SHA256");
    println!("cargo:rerun-if-env-changed=CORE_NAME");
    println!("cargo:rerun-if-env-changed=TOKEN");
}
