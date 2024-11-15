#!/bin/bash

#  clean-config.sh
#  AdobeDownloader
#
#  Created by X1a0He on 2024/11/15.
#  Copyright © 2024 X1a0He. All rights reserved.
sudo /usr/bin/killall -u root -9 Adobe\ Downloader
sudo /bin/launchctl unload /Library/LaunchDaemons/com.x1a0he.macOS.Adobe-Downloader.helper.plist
sudo /bin/rm /Library/LaunchDaemons/com.x1a0he.macOS.Adobe-Downloader.helper.plist
sudo /bin/rm /Library/PrivilegedHelperTools/com.x1a0he.macOS.Adobe-Downloader.helper
sudo /bin/rm -rf ~/Library/Application\ Support/Adobe\ Downloader
sudo /bin/rm ~/Library/Preferences/com.x1a0he.macOS.Adobe-Downloader.plist
sudo /usr/bin/killall -u root -9 com.x1a0he.macOS.Adobe-Downloader.helper