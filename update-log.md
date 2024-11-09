# Change Log

- 2024-11-09 23:00 更新日志

[//]: # (1.1.0)

```markdown
1. 修复了初次启动程序时，默认下载目录为 "Downloads" 导致提示 你不能存储文件“ILST”，因为该宗卷是只读宗卷 的问题
2. 新的实现取代了 windowResizability 以适应 macOS 12.0+（可能）
3. 新增下载记录持久化功能(M1 Max macOS 15上测试正常，未测试其他机型)

PS: 此版本改动略大，如有bugs，请及时提出
====================

1. Fixed the issue that when launching the program for the first time, the default directory is "Downloads", which
   causes a download error message
2. New implementation replaces windowResizability to adapt to macOS 12.0+ (Maybe)
3. Added task record persistence(Tested normally on M1 Max macOS 15, other models not tested)

PS: This version has been slightly changed. If there are any bugs, please report them in time.
```

- 2024-11-07 21:10 更新日志

[//]: # (1.0.1)

```markdown
1. 修复了当系统版本低于 macOS 14.6 时无法打开程序的问题，现已支持 macOS 13.0 以上
2. 增加 Sparkle 用于检测更新
3. 当默认目录为 未选择 时，将 下载 文件夹作为默认目录
4. 当通过 Adobe Downloader 安装遇到权限问题时，提供终端命令让用户自行安装
5. 调整了文件已存在的 UI 显示
6. 修复了在任务下载中，已下载包与总包数量不更新的问题

====================

1. Support macOS 13.0 and above
2. Added Sparkle for checking update
3. When the default directory is not selected, the Downloads folder will be used as the default directory
4. When installing via Adobe Downloader and encountering permission issues, provide terminal commands to allow users to
   install by themselves
5. Adjusted the UI display of existing files
6. Fixed the issue where the number of downloaded packages and total packages was not updated during task download
```

<img width="1064" alt="image" src="https://github.com/user-attachments/assets/84f3f1de-a429-45ca-9b29-948234b4fcdb">

<img width="530" alt="image" src="https://github.com/user-attachments/assets/7a22ea27-449b-42cf-8142-fce1215c5d12">

<img width="427" alt="image" src="https://github.com/user-attachments/assets/403b20db-4014-4645-8833-3616390b17fb">

<img width="880" alt="image" src="https://github.com/user-attachments/assets/b6b04cd9-bfdf-4cdd-b14c-6dcd48b376a7">

- 2024-11-06 15:50 更新日志

```markdown
1. 增加程序首次启动时的默认配置设定与提示
2. 增加可选架构下载，请在设置中进行选择
3. 修复了版本已存在检测错误的问题 (仅检测文件是否存在，并不会检测是否完整)
4. 移除主界面的语言选择和目录选择，移动到了设置中
5. 版本选择页面增加架构提示
6. 移除了安装程序的机制，现在不会再生成安装程序
7. 增加了Adobe Creative Cloud安装检测，未安装前无法使用

====================

1. Added default configuration settings and prompts when the program is started for the first time
2. Added optional architecture downloads, please select in settings
3. Fixed the problem of version detection error (only checks whether the file exists, not whether it is complete)
4. Removed the language selection and directory selection on the main interface and moved them to settings
5. Added architecture prompts on the version selection page
6. Removed the installer mechanism, and now no installer will be generated
7. Added Adobe Creative Cloud installation detection, which cannot be used before installation
```

- 2024-11-05 21:15 更新日志

```markdown
1. 增加Intel机型的Setup处理，感谢@aronychen

====================

1. Added Setup processing for Intel chips, thanks @aronychen
```

----

- 2024-11-05 15:05 更新日志

```markdown
1. 初始化仓库

====================

1. Init repo
```