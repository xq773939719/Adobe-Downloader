# Adobe Downloader

![preview](imgs/Adobe%20Downloader.png)

# **[中文版本](readme.md)**

## Before Use

**🍎Only for macOS 12.0+.**

> **If you like Adobe Downloader, or it helps you, please Star🌟 it.**
>
> 1. Before installing Adobe products, the Adobe Setup component must be present on your system; otherwise, the
     installation feature will not work. You can download it through the built-in “Settings” in the program or
     from [Adobe Creative Cloud](https://creativecloud.adobe.com/apps/download/creative-cloud).
> 2. To enable smooth installation after downloading, Adobe Downloader needs to modify Adobe’s Setup program. This
     process is fully automated by the program and requires no user intervention. Many thanks
     to [QiuChenly](https://github.com/QiuChenly) for providing the solution.
> 3. If you encounter any problems, don't panic, contact [@X1a0He](https://t.me/X1a0He) on Telegram or use the Python
     version. Many thanks to [Drovosek01](https://github.com/Drovosek01) for
     the [adobe-packager](https://github.com/Drovosek01/adobe-packager)
> 4. ⚠️⚠️⚠️ **All Adobe apps in Adobe Downloader are from official Adobe channels and are not cracked versions.**
> 5. ❌❌❌ **Do not use an external hard drive or any USB to store it, as this will cause permission issues, I do not have
     the patience to solve any about permission issues**
> 6. ❌❌❌ **Due to permission reasons, there may be problems with installation on hackintosh**

## FAQ

**This section will be updated periodically with meaningful issues that have been raised.**

### Questions about the Setup Component

> It’s mentioned in the usage instructions that to use the installation feature, you need to modify Adobe’s setup
> component. You can find details in the code.

Why is this necessary? Without modifications, installation will fail with error code 2700.

> **Does the setup modification require user intervention?**

No, Adobe Downloader automates the setup component handling, including backup. All you need to do is enter your password
when prompted.

### About Entering Your Password in the Program

> Why do I need to enter my password when installing the setup component?

Since the setup component is downloaded from GitHub and written to your system, sudo permission is required.

> Is my password sent online when downloading from GitHub?

No, it isn’t. Each time you enter your password, Adobe Downloader uses a system prompt, so your password is securely
handled by your operating system. Only you know your password and Adobe Downloader doesn’t have access to it.

> Why am I asked for my password multiple times? In what situations will I need to enter it?

1. During the download and installation of the setup component.
2. When backing up and modifying the setup component.
3. When installing Adobe apps using the setup component.
4. Anytime an operation requires elevated permissions (as before, you can safely enter your password).

## 📔Latest Log

- For historical update logs, please go to [Update Log](update-log.md)

- 2024-11-11 21:00 Update Log

```markdown
1. Adjust the order of sheet pop-up when the program starts
2. Added detection of Setup components and version number detection in settings, supporting re-backup and processing in
   settings
3. Adjusted detection of Setup components, no longer requiring full installation of Adobe Creative Cloud
4. Added judgment of whether Setup components have been processed before installation. If Setup components are not
   processed, the installation function cannot be used
5. Adjusted the pop-up interface of Setup component detection
6. Added downloading of Setup components from GitHub. Users who cannot access GitHub may encounter problems with
   download failure

PS: The sources of Setup components are all extracted from Adobe Creative Cloud, so they may not be updated in time.
```

### Language friendly

- [x] Chinese
- [x] English

## ⚠️ Warning

**For all the SwiftUI seniors, I am just a SwiftUI newbie, some of the code comes from Claude, OpenAI and Apple, etc.**
\
**If you have any optimization suggestions or questions about Adobe Downloader, please open an issue or contact @X1a0He
via Telegram.**

## ✨ Features

- [x] Basic Functionality
    - [x] Download Acrobat Pro
    - [x] Download other Adobe products
    - [x] Support installation of non-Acrobat products
    - [x] Support multiple products download at the same time
    - [x] Supports using default language and default directory
    - [x] Support task record persistence

## 👀 Preview

### Light Mode & Dark Mode

![light](imgs/preview-light.png)
![dark](imgs/preview-dark.png)

### Version Picker

![version picker](imgs/version.png)

### Language Picker

![language picker](imgs/language.png)

### Download Management

![download management](imgs/download.png)

## 🔗 References

- [Drovosek01/adobe-packager](https://github.com/Drovosek01/adobe-packager/)
- [QiuChenly/InjectLib](https://github.com/QiuChenly/InjectLib/)

## 👨🏻‍💻Author

Adobe Downloader © X1a0He

Released under GPLv3. Created on 2024.11.05.

> GitHub [@X1a0He](https://github.com/X1a0He/) \
> Telegram [@X1a0He](https://t.me/X1a0He)
