<div>

[**简体中文**](README_zh_CN.md)

</div>

## Sororain

[![Last Version](https://img.shields.io/github/release/sororain/FlClash/all.svg?style=flat-square)](https://github.com/sororain/FlClash/releases)[![License](https://img.shields.io/github/license/sororain/FlClash?style=flat-square)](LICENSE)

[![Channel](https://img.shields.io/badge/Telegram-Channel-blue?style=flat-square&logo=telegram)](https://t.me/sororain)

A modern cross-platform proxy client with a clean, intuitive, and smooth user experience.

on Desktop:
<p style="text-align: center;">
    <img alt="desktop" src="snapshots/desktop.gif">
</p>

on Mobile:
<p style="text-align: center;">
    <img alt="mobile" src="snapshots/mobile.gif">
</p>

## Features

✈️ Multi-platform: Android, Windows, macOS and Linux

💻 Adaptive multiple screen sizes, Multiple color themes available

💡 Based on Material You Design, [Surfboard](https://github.com/getsurfboard/surfboard)-like UI

☁️ Supports data sync via WebDAV

✨ Support subscription link, Dark mode

## Use

### Linux

⚠️ Make sure to install the following dependencies before using them

   ```bash
    sudo apt-get install libayatana-appindicator3-dev
    sudo apt-get install libkeybinder-3.0-dev
   ```

### Android

Support the following actions

   ```bash
    com.sororain.clash.action.START
    
    com.sororain.clash.action.STOP
    
    com.sororain.clash.action.TOGGLE
   ```

## Download

[![Get it on GitHub](https://img.shields.io/badge/Download-GitHub_Releases-blue?style=flat-square&logo=github)](https://github.com/sororain/FlClash/releases)

## Build

1. Update submodules
   ```bash
   git submodule update --init --recursive
   ```

2. Install `Flutter` and `Golang` environment

3. Build Application

    - android

        1. Install `Android SDK`, `Android NDK`

        2. Set `ANDROID_NDK` environment variable

        3. Run build script

           ```bash
           dart setup.dart android
           ```

    - windows

        1. Requires a Windows client

        2. Install `Flutter`, `Visual Studio 2022` (C++ workload), `CMake`, `Go 1.20+`, `Rust`, `Inno Setup`

        3. Run build script

           ```bash
           dart setup.dart windows
           ```

    - linux

        1. Requires a Linux client

        2. Dependencies are auto-installed by setup script, or manually:
           ```bash
           sudo apt-get install -y libayatana-appindicator3-dev libkeybinder-3.0-dev
           ```

        3. Run build script

           ```bash
           dart setup.dart linux
           ```

    - macOS

        1. Requires a macOS client

        2. Run build script

           ```bash
           dart setup.dart macos
           ```

## Star

The easiest way to support developers is to click on the star (⭐) at the top of the page.

<p style="text-align: center;">
    <a href="https://api.star-history.com/svg?repos=sororain/FlClash&Date">
        <img alt="start" width=50% src="https://api.star-history.com/svg?repos=sororain/FlClash&Date"/>
    </a>
</p>