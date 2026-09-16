<div>

[**English**](README.md)

</div>

## Sororain

[![Channel](https://img.shields.io/badge/Telegram-Channel-blue?style=flat-square&logo=telegram)](https://t.me/sororain)

现代化的跨平台代理客户端，提供简洁流畅的使用体验

on Desktop:
<p style="text-align: center;">
    <img alt="desktop" src="snapshots/desktop.gif">
</p>

on Mobile:
<p style="text-align: center;">
    <img alt="mobile" src="snapshots/mobile.gif">
</p>

## Features

✈️ 多平台: Android, Windows, macOS and Linux

💻 自适应多个屏幕尺寸,多种颜色主题可供选择

💡 基本 Material You 设计, 类[Surfboard](https://github.com/getsurfboard/surfboard)用户界面

☁️ 支持通过WebDAV同步数据

✨ 支持一键导入订阅, 深色模式

## Use

### Linux

⚠️ 使用前请确保安装以下依赖

   ```bash
    sudo apt-get install libayatana-appindicator3-dev
    sudo apt-get install libkeybinder-3.0-dev
   ```

### Android

支持下列操作

   ```bash
    com.sororain.clash.action.START
    
    com.sororain.clash.action.STOP
    
    com.sororain.clash.action.TOGGLE
   ```

## Build

1. 更新 submodules
   ```bash
   git submodule update --init --recursive
   ```

2. 安装 `Flutter` 以及 `Golang` 环境

3. 构建应用

    - android

        1. 安装 `Android SDK`、`Android NDK`，并配置 `ANDROID_NDK` 环境变量

        2. 运行构建脚本

           ```bash
           dart setup.dart android
           ```

    - windows

        1. 需要 Windows 主机

        2. 安装 `build_env_checklist.txt` 里列出的工具链

        3. 运行构建脚本

           ```bash
           dart setup.dart windows
           ```

    - linux

        1. 需要 Linux 主机

        2. 依赖会由 setup 脚本自动安装，也可以手动安装：
           ```bash
           sudo apt-get install -y libayatana-appindicator3-dev libkeybinder-3.0-dev
           ```

        3. 运行构建脚本

           ```bash
           dart setup.dart linux
           ```

    - macOS

        1. 需要 macOS 主机

        2. 安装 `build_env_checklist.txt` 里列出的工具链

        3. 运行构建脚本

           ```bash
           dart setup.dart macos
           ```
