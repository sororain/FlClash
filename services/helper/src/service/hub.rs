use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::VecDeque;
use std::fs::File;
use std::io::{BufRead, Error, Read};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::{io, thread};
use warp::{Filter, Reply};

const LISTEN_PORT: u16 = 47890;

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct StartParams {
    pub path: String,
    pub arg: String,
}

fn sha256_file(path: &str) -> Result<String, Error> {
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

    Ok(format!("{:x}", hasher.finalize()))
}

static LOGS: Lazy<Arc<Mutex<VecDeque<String>>>> =
    Lazy::new(|| Arc::new(Mutex::new(VecDeque::with_capacity(100))));
static PROCESS: Lazy<Arc<Mutex<Option<std::process::Child>>>> =
    Lazy::new(|| Arc::new(Mutex::new(None)));

/// Windows 没有 cgroup 可以随 helper 一起带走 Core，于是把 Core 放进一个 job：
/// helper 进程消失（崩溃/被卸载/被强杀）时由内核把它一起收掉，避免留下无人管理的
/// Core 以及它挂上的 sing-tun 路由。
#[cfg(windows)]
struct CoreJob(isize);

#[cfg(windows)]
impl CoreJob {
    fn bind(child: &std::process::Child) -> io::Result<Self> {
        use std::os::windows::io::AsRawHandle;
        use windows_sys::Win32::System::JobObjects::{
            AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation,
            SetInformationJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
            JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
        };

        // SAFETY: 只调用 kernel32，句柄归本进程所有；job 句柄由 Drop 关闭，
        // 进程句柄仍归 child。
        unsafe {
            let job = CreateJobObjectW(std::ptr::null(), std::ptr::null());
            if job.is_null() {
                return Err(io::Error::last_os_error());
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
                return Err(io::Error::last_os_error());
            }
            if AssignProcessToJobObject(job.0 as _, child.as_raw_handle() as _) == 0 {
                return Err(io::Error::last_os_error());
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
            windows_sys::Win32::Foundation::CloseHandle(self.0 as _);
        }
    }
}

#[cfg(windows)]
static JOB: Lazy<Arc<Mutex<Option<CoreJob>>>> = Lazy::new(|| Arc::new(Mutex::new(None)));

fn start(start_params: StartParams) -> impl Reply {
    if !cfg!(debug_assertions) {
        let sha256 = sha256_file(start_params.path.as_str()).unwrap_or("".to_string());
        if sha256 != env!("TOKEN") {
            return format!("The SHA256 hash of the program requesting execution is: {}. The helper program only allows execution of applications with the SHA256 hash: {}.", sha256,  env!("TOKEN"),);
        }
    }
    stop();
    let mut process = PROCESS.lock().unwrap();
    match Command::new(&start_params.path)
        .stderr(Stdio::piped())
        .arg(&start_params.arg)
        .spawn()
    {
        Ok(child) => {
            *process = Some(child);
            #[cfg(windows)]
            {
                // 绑定失败不阻断启动（例如进程已在别的 job 里）：只是失去
                // “helper 崩溃时内核回收 Core”这层保护，记日志即可。
                match CoreJob::bind(process.as_ref().unwrap()) {
                    Ok(job) => *JOB.lock().unwrap() = Some(job),
                    Err(error) => log_message(format!(
                        "Failed to bind the Core to a job object: {error}"
                    )),
                }
            }
            if let Some(ref mut child) = *process {
                let stderr = child.stderr.take().unwrap();
                let reader = io::BufReader::new(stderr);
                thread::spawn(move || {
                    for line in reader.lines() {
                        match line {
                            Ok(output) => {
                                log_message(output);
                            }
                            Err(_) => {
                                break;
                            }
                        }
                    }
                });
            }
            "".to_string()
        }
        Err(e) => {
            log_message(e.to_string());
            e.to_string()
        }
    }
}

fn stop() -> impl Reply {
    let mut process = PROCESS.lock().unwrap();
    if let Some(mut child) = process.take() {
        let _ = child.kill();
        let _ = child.wait();
    }
    *process = None;
    #[cfg(windows)]
    {
        // 丢掉 job 句柄（KILL_ON_JOB_CLOSE 也会顺带收掉可能残留的 Core）。
        *JOB.lock().unwrap() = None;
    }
    "".to_string()
}

fn log_message(message: String) {
    let mut log_buffer = LOGS.lock().unwrap();
    if log_buffer.len() == 100 {
        log_buffer.pop_front();
    }
    log_buffer.push_back(format!("{}\n", message));
}

fn get_logs() -> impl Reply {
    let log_buffer = LOGS.lock().unwrap();
    let value = log_buffer
        .iter()
        .cloned()
        .collect::<Vec<String>>()
        .join("\n");
    warp::reply::with_header(value, "Content-Type", "text/plain")
}

pub async fn run_service() -> anyhow::Result<()> {
    let api_ping = warp::get().and(warp::path("ping")).map(|| env!("TOKEN"));

    let api_start = warp::post()
        .and(warp::path("start"))
        .and(warp::body::json())
        .map(|start_params: StartParams| start(start_params));

    let api_stop = warp::post().and(warp::path("stop")).map(|| stop());

    let api_logs = warp::get().and(warp::path("logs")).map(|| get_logs());

    warp::serve(api_ping.or(api_start).or(api_stop).or(api_logs))
        .run(([127, 0, 0, 1], LISTEN_PORT))
        .await;

    Ok(())
}
