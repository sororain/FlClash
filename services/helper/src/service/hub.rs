use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::VecDeque;
use std::fs::File;
use std::io::{BufRead, Error, Read};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::{Mutex, MutexGuard};
use std::time::{Duration, Instant};
use std::{io, thread};
use warp::http::StatusCode;
use warp::{Filter, Rejection, Reply};

#[cfg(windows)]
use std::os::windows::io::AsRawHandle;
#[cfg(windows)]
use windows_sys::Win32::Foundation::CloseHandle;
#[cfg(windows)]
use windows_sys::Win32::System::JobObjects::{
    AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation,
    SetInformationJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
    JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
};

const LISTEN_PORT: u16 = 47890;
/// App 侧的地址形如 `\\.\pipe\SororainCore_<32 位小写 hex>`，后缀同时就是 sessionId
/// （见 lib/common/constant.dart 的 windowsPipeName），所以白名单靠前缀 + hex 校验即可。
const CORE_PIPE_PREFIX: &str = r"\\.\pipe\SororainCore_";
const PROTOCOL_VERSION_HEADER: &str = "x-sororain-helper-protocol";
const PROTOCOL_VERSION: &str = "6";
const EXPECTED_CORE_SHA256: &str = env!("CORE_SHA256");
const CORE_NAME: &str = env!("CORE_NAME");
const LOG_CAPACITY: usize = 100;
const CORE_EXIT_TIMEOUT: Duration = Duration::from_millis(1500);
const CORE_EXIT_POLL_INTERVAL: Duration = Duration::from_millis(20);

#[derive(Debug, Deserialize, Serialize, Clone)]
#[serde(deny_unknown_fields)]
pub struct StartParams {
    pub address: String,
    #[serde(rename = "sessionId")]
    pub session_id: String,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
#[serde(deny_unknown_fields)]
pub struct StopParams {
    #[serde(rename = "sessionId")]
    pub session_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct PingParams {
    #[serde(rename = "coreSha256")]
    core_sha256: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct StartResponse {
    session_id: String,
    pid: u32,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct StopResponse {
    session_id: String,
    stopped: bool,
    reason: Option<&'static str>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ErrorResponse {
    code: &'static str,
    message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    details: Option<ErrorDetails>,
}

/// App 靠 osError 区分“Windows 基于策略拒绝执行”（Smart App Control / AppLocker）
/// 与“core 本身是坏的”。
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ErrorDetails {
    os_error: i32,
}

/// Windows 没有 cgroup 可以随 helper 一起带走 Core，于是把 Core 放进一个 job：
/// helper 进程消失（崩溃/被卸载/被强杀）时由内核把它一起收掉，避免留下无人管理的
/// Core 以及它挂上的 sing-tun 路由。
#[cfg(windows)]
struct CoreJob(isize);

#[cfg(windows)]
impl CoreJob {
    fn bind(child: &Child) -> Result<Self, Error> {
        // SAFETY: 只调用 kernel32，句柄归本进程所有；job 句柄由 Drop 关闭，
        // 进程句柄仍归 child。
        unsafe {
            let job = CreateJobObjectW(std::ptr::null(), std::ptr::null());
            if job.is_null() {
                return Err(Error::last_os_error());
            }
            let job = Self(job as isize);
            let mut limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = std::mem::zeroed();
            limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            if SetInformationJobObject(
                job.0 as _,
                JobObjectExtendedLimitInformation,
                &limits as *const _ as *const _,
                std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
            ) == 0
            {
                return Err(Error::last_os_error());
            }
            if AssignProcessToJobObject(job.0 as _, child.as_raw_handle() as _) == 0 {
                return Err(Error::last_os_error());
            }
            Ok(job)
        }
    }
}

#[cfg(windows)]
impl Drop for CoreJob {
    fn drop(&mut self) {
        // SAFETY: 句柄来自 CreateJobObjectW，只关闭一次。
        unsafe {
            CloseHandle(self.0 as _);
        }
    }
}

struct ManagedCore {
    session_id: String,
    child: Child,
    #[cfg(windows)]
    _job: CoreJob,
}

impl ManagedCore {
    fn adopt(session_id: String, child: Child) -> Result<Self, Error> {
        #[cfg(windows)]
        {
            let job = CoreJob::bind(&child)?;
            Ok(Self {
                session_id,
                child,
                _job: job,
            })
        }
        #[cfg(not(windows))]
        {
            Ok(Self { session_id, child })
        }
    }

    /// helper 只支持 Windows，没有 SIGTERM 可以请求优雅退出（Linux 上那是让 core
    /// 自己清掉 sing-tun 路由的手段），所以直接强杀再轮询确认退出。
    fn terminate(&mut self) -> Result<(), Error> {
        let _ = self.child.kill();
        if wait_for_core_end(&mut self.child, CORE_EXIT_TIMEOUT)? {
            return Ok(());
        }
        Err(Error::other("Core did not exit after being killed"))
    }
}

fn wait_for_core_end(child: &mut Child, timeout: Duration) -> Result<bool, Error> {
    let deadline = Instant::now() + timeout;
    loop {
        if child.try_wait()?.is_some() {
            return Ok(true);
        }
        if Instant::now() >= deadline {
            return Ok(false);
        }
        thread::sleep(CORE_EXIT_POLL_INTERVAL);
    }
}

struct VerifiedCore {
    path: PathBuf,
    directory: PathBuf,
}

impl VerifiedCore {
    fn open() -> Result<Self, Error> {
        let path = core_path()?;
        let directory = path
            .parent()
            .ok_or_else(|| Error::other("Core executable has no parent directory"))?
            .to_path_buf();
        verify_core(&path, EXPECTED_CORE_SHA256)?;
        Ok(Self { path, directory })
    }

    fn spawn(&self, address: &str) -> Result<Child, Error> {
        Command::new(&self.path)
            .current_dir(&self.directory)
            .stderr(Stdio::piped())
            .arg(address)
            .spawn()
    }
}

fn core_path() -> Result<PathBuf, Error> {
    let helper_path = std::env::current_exe()?;
    let directory = helper_path
        .parent()
        .ok_or_else(|| Error::other("helper executable has no parent directory"))?;
    Ok(directory.join(CORE_NAME))
}

fn verify_core(path: &Path, expected_sha256: &str) -> Result<(), Error> {
    if expected_sha256.is_empty() {
        return Err(Error::other("expected Core SHA256 is empty"));
    }
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0; 4096];
    loop {
        let bytes_read = file.read(&mut buffer)?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }
    if format!("{:x}", hasher.finalize()) != expected_sha256 {
        return Err(Error::other("Core executable SHA256 mismatch"));
    }
    Ok(())
}

fn is_valid_session_id(value: &str) -> bool {
    value.len() == 32
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn is_allowed_core_address(address: &str) -> bool {
    let Some(suffix) = address.strip_prefix(CORE_PIPE_PREFIX) else {
        return false;
    };
    is_valid_session_id(suffix)
}

#[derive(Debug, PartialEq, Eq)]
enum StopDecision {
    NotRunning,
    Stop,
    SessionMismatch,
}

fn stop_decision(current: Option<&str>, requested: &str) -> StopDecision {
    match current {
        None => StopDecision::NotRunning,
        Some(session_id) if session_id == requested => StopDecision::Stop,
        Some(_) => StopDecision::SessionMismatch,
    }
}

static LOGS: Lazy<Mutex<VecDeque<String>>> =
    Lazy::new(|| Mutex::new(VecDeque::with_capacity(LOG_CAPACITY)));
static MANAGED_CORE: Lazy<Mutex<Option<ManagedCore>>> = Lazy::new(|| Mutex::new(None));

/// 一个 handler panic 会毒化 mutex；对 helper 来说带着毒化继续服务，比之后所有
/// 请求都失败要好。
fn lock_surviving_poison<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn release_managed_core(managed: &mut Option<ManagedCore>) -> Result<(), Error> {
    let Some(core) = managed.as_mut() else {
        return Ok(());
    };
    core.terminate()?;
    *managed = None;
    Ok(())
}

fn json_response<T: Serialize>(value: &T, status: StatusCode) -> warp::reply::Response {
    warp::reply::with_status(warp::reply::json(value), status).into_response()
}

fn with_protocol_header(reply: impl Reply) -> warp::reply::Response {
    warp::reply::with_header(reply, PROTOCOL_VERSION_HEADER, PROTOCOL_VERSION).into_response()
}

fn error_response(
    code: &'static str,
    message: impl Into<String>,
    status: StatusCode,
) -> warp::reply::Response {
    json_response(
        &ErrorResponse {
            code,
            message: message.into(),
            details: None,
        },
        status,
    )
}

/// App 靠 osError 区分“被系统策略拒绝”与“core 坏了”，所以启动失败要带上它。
fn launch_failure_response(error: &Error) -> warp::reply::Response {
    json_response(
        &ErrorResponse {
            code: "processLaunchFailed",
            message: error.to_string(),
            details: error
                .raw_os_error()
                .map(|os_error| ErrorDetails { os_error }),
        },
        StatusCode::INTERNAL_SERVER_ERROR,
    )
}

async fn ping_request(params: PingParams) -> Result<impl Reply, Rejection> {
    if EXPECTED_CORE_SHA256.is_empty() {
        log_message("Helper was built without a Core SHA256".to_string());
        return Ok(with_protocol_header(error_response(
            "internalError",
            "expected Core SHA256 is empty",
            StatusCode::INTERNAL_SERVER_ERROR,
        )));
    }
    if params.core_sha256 != EXPECTED_CORE_SHA256 {
        log_message("Helper ping refused: the app reported a different Core SHA256".to_string());
        return Ok(with_protocol_header(error_response(
            "coreSha256Mismatch",
            "Core executable SHA256 mismatch",
            StatusCode::CONFLICT,
        )));
    }
    let core_available = match core_path() {
        Ok(path) => File::open(path).is_ok(),
        Err(_) => false,
    };
    if !core_available {
        log_message("Helper ping refused: the Core executable is not accessible".to_string());
        return Ok(with_protocol_header(error_response(
            "coreUnavailable",
            "Helper could not access the Core executable",
            StatusCode::CONFLICT,
        )));
    }
    // App 会把自己期望的 helper 路径与这里返回的路径比对，防的是“同名进程冒充”。
    let helper_path = std::env::current_exe()
        .map(|path| path.to_string_lossy().into_owned())
        .unwrap_or_default();
    Ok(with_protocol_header(warp::reply::with_header(
        helper_path,
        "Content-Type",
        "text/plain",
    )))
}

async fn start_request(start_params: StartParams) -> Result<impl Reply, Rejection> {
    if !is_allowed_core_address(&start_params.address) {
        return Ok(with_protocol_header(error_response(
            "invalidRequest",
            "invalid Core address",
            StatusCode::BAD_REQUEST,
        )));
    }
    if !is_valid_session_id(&start_params.session_id) {
        return Ok(with_protocol_header(error_response(
            "invalidRequest",
            "invalid Core session ID",
            StatusCode::BAD_REQUEST,
        )));
    }

    let mut managed = lock_surviving_poison(&MANAGED_CORE);
    if let Err(error) = release_managed_core(&mut managed) {
        log_message(format!(
            "Helper could not release the managed Core: {error}"
        ));
        return Ok(with_protocol_header(error_response(
            "coreStopFailed",
            error.to_string(),
            StatusCode::INTERNAL_SERVER_ERROR,
        )));
    }

    let core = match VerifiedCore::open() {
        Ok(core) => core,
        Err(error) => {
            log_message(format!("Helper refused to start the Core: {error}"));
            return Ok(with_protocol_header(error_response(
                "coreVerificationFailed",
                error.to_string(),
                StatusCode::CONFLICT,
            )));
        }
    };

    match core.spawn(&start_params.address) {
        Ok(mut child) => {
            let process_id = child.id();
            if let Some(stderr) = child.stderr.take() {
                let reader = io::BufReader::new(stderr);
                thread::spawn(move || {
                    for line in reader.lines() {
                        match line {
                            Ok(output) => log_message(output),
                            Err(_) => break,
                        }
                    }
                });
            }
            let session_id = start_params.session_id.clone();
            match ManagedCore::adopt(start_params.session_id, child) {
                Ok(adopted) => {
                    *managed = Some(adopted);
                }
                Err(error) => {
                    log_message(format!("Helper could not confine the Core: {error}"));
                    return Ok(with_protocol_header(error_response(
                        "internalError",
                        format!("Core confinement failed: {error}"),
                        StatusCode::INTERNAL_SERVER_ERROR,
                    )));
                }
            }
            Ok(with_protocol_header(json_response(
                &StartResponse {
                    session_id,
                    pid: process_id,
                },
                StatusCode::OK,
            )))
        }
        Err(error) => {
            log_message(format!("Helper could not launch the Core: {error}"));
            Ok(with_protocol_header(launch_failure_response(&error)))
        }
    }
}

async fn stop_request(stop_params: StopParams) -> Result<impl Reply, Rejection> {
    if !is_valid_session_id(&stop_params.session_id) {
        return Ok(with_protocol_header(error_response(
            "invalidRequest",
            "invalid Core session ID",
            StatusCode::BAD_REQUEST,
        )));
    }

    let mut managed = lock_surviving_poison(&MANAGED_CORE);
    let current = managed.as_ref().map(|core| core.session_id.as_str());
    match stop_decision(current, &stop_params.session_id) {
        StopDecision::NotRunning => Ok(with_protocol_header(json_response(
            &StopResponse {
                session_id: stop_params.session_id,
                stopped: false,
                reason: Some("notRunning"),
            },
            StatusCode::OK,
        ))),
        StopDecision::SessionMismatch => Ok(with_protocol_header(json_response(
            &serde_json::json!({ "reason": "sessionMismatch" }),
            StatusCode::CONFLICT,
        ))),
        StopDecision::Stop => {
            if let Err(error) = release_managed_core(&mut managed) {
                log_message(format!("Helper could not stop the Core: {error}"));
                return Ok(with_protocol_header(error_response(
                    "coreStopFailed",
                    error.to_string(),
                    StatusCode::INTERNAL_SERVER_ERROR,
                )));
            }
            Ok(with_protocol_header(json_response(
                &StopResponse {
                    session_id: stop_params.session_id,
                    stopped: true,
                    reason: None,
                },
                StatusCode::OK,
            )))
        }
    }
}

fn log_message(message: String) {
    let mut log_buffer = lock_surviving_poison(&LOGS);
    if log_buffer.len() == LOG_CAPACITY {
        log_buffer.pop_front();
    }
    log_buffer.push_back(format!("{}\n", message));
}

fn get_logs() -> impl Reply {
    let log_buffer = lock_surviving_poison(&LOGS);
    let value = log_buffer
        .iter()
        .cloned()
        .collect::<Vec<String>>()
        .join("\n");
    warp::reply::with_header(value, "Content-Type", "text/plain")
}

async fn handle_rejection(rejection: Rejection) -> Result<impl Reply, Rejection> {
    if rejection.is_not_found() {
        return Ok(with_protocol_header(error_response(
            "notFound",
            "Helper endpoint not found",
            StatusCode::NOT_FOUND,
        )));
    }
    if rejection
        .find::<warp::filters::body::BodyDeserializeError>()
        .is_some()
    {
        return Ok(with_protocol_header(error_response(
            "invalidRequest",
            "invalid JSON request body",
            StatusCode::BAD_REQUEST,
        )));
    }
    if rejection.find::<warp::reject::InvalidQuery>().is_some() {
        return Ok(with_protocol_header(error_response(
            "invalidRequest",
            "invalid or missing query parameters",
            StatusCode::BAD_REQUEST,
        )));
    }
    if rejection.find::<warp::reject::MethodNotAllowed>().is_some() {
        return Ok(with_protocol_header(error_response(
            "invalidRequest",
            "Helper endpoint does not accept this method",
            StatusCode::METHOD_NOT_ALLOWED,
        )));
    }
    Ok(with_protocol_header(error_response(
        "internalError",
        "unhandled Helper request rejection",
        StatusCode::INTERNAL_SERVER_ERROR,
    )))
}

fn routes() -> impl Filter<Extract = (impl Reply,), Error = Rejection> + Clone {
    // 先匹配路径再匹配方法：这样未知路径会报 not found，而不是别的端点的方法不匹配。
    let api_ping = warp::path("ping")
        .and(warp::path::end())
        .and(warp::get())
        .and(warp::query::<PingParams>())
        .and_then(ping_request);

    let api_start = warp::path("start")
        .and(warp::path::end())
        .and(warp::post())
        .and(warp::body::json())
        .and_then(start_request);

    let api_stop = warp::path("stop")
        .and(warp::path::end())
        .and(warp::post())
        .and(warp::body::json())
        .and_then(stop_request);

    let api_logs = warp::path("logs")
        .and(warp::path::end())
        .and(warp::get())
        .map(get_logs);

    api_ping
        .or(api_start)
        .or(api_stop)
        .or(api_logs)
        .recover(handle_rejection)
}

pub async fn run_service() -> anyhow::Result<()> {
    if EXPECTED_CORE_SHA256.is_empty() {
        anyhow::bail!("expected Core SHA256 is empty");
    }
    warp::serve(routes()).run(([127, 0, 0, 1], LISTEN_PORT)).await;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use warp::http::Response;

    const SESSION_ID: &str = "0123456789abcdef0123456789abcdef";
    const CORE_ADDRESS: &str = r"\\.\pipe\SororainCore_0123456789abcdef0123456789abcdef";

    fn body_text(response: &Response<impl AsRef<[u8]>>) -> String {
        String::from_utf8_lossy(response.body().as_ref()).into_owned()
    }

    fn protocol_header(response: &Response<impl AsRef<[u8]>>) -> String {
        response
            .headers()
            .get(PROTOCOL_VERSION_HEADER)
            .expect("every reply carries the protocol version")
            .to_str()
            .unwrap()
            .to_string()
    }

    /// 地址白名单只认形状：固定前缀 + 32 位小写 hex。
    #[test]
    fn accepts_only_the_core_pipe_shape() {
        assert!(is_allowed_core_address(CORE_ADDRESS));
        assert!(!is_allowed_core_address(
            r"\\.\pipe\SororainCore_0123456789abcdef0123456789abcde"
        ));
        assert!(!is_allowed_core_address(
            r"\\.\pipe\SororainCore_0123456789ABCDEF0123456789ABCDEF"
        ));
        assert!(!is_allowed_core_address(
            r"\\.\pipe\SororainCore_zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"
        ));
        assert!(!is_allowed_core_address(
            r"\\.\pipe\Other_0123456789abcdef0123456789abcdef"
        ));
        assert!(!is_allowed_core_address(""));
    }

    #[test]
    fn accepts_only_a_32_hex_lowercase_session_id() {
        assert!(is_valid_session_id(SESSION_ID));
        assert!(!is_valid_session_id(""));
        assert!(!is_valid_session_id("0123456789abcdef0123456789abcde"));
        assert!(!is_valid_session_id("0123456789abcdef0123456789abcdez"));
        assert!(!is_valid_session_id("0123456789ABCDEF0123456789ABCDEF"));
    }

    #[test]
    fn stop_decision_covers_the_three_cases() {
        assert_eq!(stop_decision(None, SESSION_ID), StopDecision::NotRunning);
        assert_eq!(
            stop_decision(Some(SESSION_ID), SESSION_ID),
            StopDecision::Stop
        );
        assert_eq!(
            stop_decision(Some(SESSION_ID), "ffffffffffffffffffffffffffffffff"),
            StopDecision::SessionMismatch
        );
    }

    #[test]
    fn verify_core_compares_the_sha256_of_the_file() {
        let path = std::env::temp_dir().join("sororain-helper-verify-core.bin");
        std::fs::write(&path, b"core bytes").unwrap();
        let mut hasher = Sha256::new();
        hasher.update(b"core bytes");
        let expected = format!("{:x}", hasher.finalize());
        assert!(verify_core(&path, &expected).is_ok());
        // 构建链没注入 SHA 时 helper 必须拒绝服务，而不是放行任意 Core。
        assert!(verify_core(&path, "").is_err());
        let other = format!("0{}", expected.get(1..).unwrap_or_default());
        assert_ne!(other, expected);
        assert!(verify_core(&path, &other).is_err());
        assert!(verify_core(&std::env::temp_dir().join("missing-core.exe"), &expected).is_err());
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    async fn ping_without_the_core_sha256_query_is_a_bad_request() {
        let response = warp::test::request().path("/ping").reply(&routes()).await;
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        assert!(body_text(&response).contains("invalidRequest"));
        assert_eq!(protocol_header(&response), PROTOCOL_VERSION);
    }

    #[tokio::test]
    async fn ping_rejects_a_core_sha256_that_does_not_match() {
        let requested = if EXPECTED_CORE_SHA256.starts_with('0') {
            format!("1{}", EXPECTED_CORE_SHA256.get(1..).unwrap_or_default())
        } else {
            format!("0{}", EXPECTED_CORE_SHA256.get(1..).unwrap_or_default())
        };
        assert_ne!(requested, EXPECTED_CORE_SHA256);
        let response = warp::test::request()
            .path(&format!("/ping?coreSha256={requested}"))
            .reply(&routes())
            .await;
        assert_eq!(protocol_header(&response), PROTOCOL_VERSION);
        if EXPECTED_CORE_SHA256.is_empty() {
            // 没被构建链注入 SHA 的 helper 连自己都不该服务（例如直接 cargo test）。
            assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
            assert!(body_text(&response).contains("internalError"));
            return;
        }
        assert_eq!(response.status(), StatusCode::CONFLICT);
        assert!(body_text(&response).contains("coreSha256Mismatch"));
    }

    #[tokio::test]
    async fn start_rejects_an_address_outside_the_core_pipe_prefix() {
        let response = warp::test::request()
            .method("POST")
            .path("/start")
            .json(&serde_json::json!({
                "address": r"\\.\pipe\Other_0123456789abcdef0123456789abcdef",
                "sessionId": SESSION_ID,
            }))
            .reply(&routes())
            .await;
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        assert!(body_text(&response).contains("invalidRequest"));
    }

    #[tokio::test]
    async fn start_rejects_a_malformed_session_id() {
        let response = warp::test::request()
            .method("POST")
            .path("/start")
            .json(&serde_json::json!({
                "address": CORE_ADDRESS,
                "sessionId": "abc",
            }))
            .reply(&routes())
            .await;
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        assert!(body_text(&response).contains("invalidRequest"));
    }

    #[tokio::test]
    async fn start_rejects_an_unknown_field() {
        let response = warp::test::request()
            .method("POST")
            .path("/start")
            .json(&serde_json::json!({
                "address": CORE_ADDRESS,
                "sessionId": SESSION_ID,
                "path": "C:/evil.exe",
            }))
            .reply(&routes())
            .await;
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        assert!(body_text(&response).contains("invalidRequest"));
    }

    /// 启动前的两个失败码之一：Core 无法核验时 App 会回退到直连启动。
    #[tokio::test]
    async fn start_refuses_a_core_it_cannot_verify() {
        if !EXPECTED_CORE_SHA256.is_empty() {
            // 带真实 SHA 的构建要走真正的核验 + 拉起进程，不适合在单测里跑。
            return;
        }
        let response = warp::test::request()
            .method("POST")
            .path("/start")
            .json(&serde_json::json!({
                "address": CORE_ADDRESS,
                "sessionId": SESSION_ID,
            }))
            .reply(&routes())
            .await;
        assert_eq!(response.status(), StatusCode::CONFLICT);
        assert!(body_text(&response).contains("coreVerificationFailed"));
    }

    #[tokio::test]
    async fn stop_of_a_core_that_is_not_running_is_ok() {
        let response = warp::test::request()
            .method("POST")
            .path("/stop")
            .json(&serde_json::json!({ "sessionId": SESSION_ID }))
            .reply(&routes())
            .await;
        assert_eq!(response.status(), StatusCode::OK);
        let body = body_text(&response);
        assert!(body.contains("notRunning"), "unexpected body: {body}");
        assert!(body.contains(SESSION_ID), "unexpected body: {body}");
        assert_eq!(protocol_header(&response), PROTOCOL_VERSION);
    }

    #[tokio::test]
    async fn stop_rejects_a_malformed_session_id() {
        let response = warp::test::request()
            .method("POST")
            .path("/stop")
            .json(&serde_json::json!({ "sessionId": "abc" }))
            .reply(&routes())
            .await;
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        assert!(body_text(&response).contains("invalidRequest"));
    }

    #[tokio::test]
    async fn logs_are_served_as_plain_text() {
        let response = warp::test::request().path("/logs").reply(&routes()).await;
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(
            response.headers().get("content-type").unwrap(),
            "text/plain"
        );
    }

    #[tokio::test]
    async fn unknown_endpoints_are_not_found_and_carry_the_protocol_header() {
        let response = warp::test::request().path("/nope").reply(&routes()).await;
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
        assert_eq!(protocol_header(&response), PROTOCOL_VERSION);
    }

    #[tokio::test]
    async fn endpoints_reject_the_wrong_method() {
        let response = warp::test::request()
            .method("GET")
            .path("/start")
            .reply(&routes())
            .await;
        assert_eq!(response.status(), StatusCode::METHOD_NOT_ALLOWED);
        assert_eq!(protocol_header(&response), PROTOCOL_VERSION);
    }
}
