# mythv-osx-build-script

Script allows to build current mythtv-master (tested on  pre-30, r769 gc580bc2) on vanilla (only Xcode required) macOS (10.13.6 tested).

It is based on excellent work of:

Copyright (c) 2012-2014 Jean-Yves Avenard

Jeremiah Morris <jm@whpress.com>



Goal for my work on this scipt was 2-fold:

1.build with prebuild Qt binaries (tested 5.11.1)

2.full automated build of working Mythfrontend.app



When compared to original osx-packager-qtsdk from MythTV packaging repo, script has following chnges:

-support only for myth-29 (not tested) and mayth-master (tested).

-remove code dealing with mythtv git sources (script assumes user already has directory with myth code for compilation).




<b>1) Preliminaries:</b>



-macOS XCode 9+ (tested on Xcode 9.4.1, build version 9F2000)

-installed prebuild Qt binaries (tested on Qt5.11.1)




<b>2) Building mythtv:</b>



-download Qt binaries

i.e. https://download.qt.io/archive/qt/5.11/5.11.1/qt-opensource-mac-x64-5.11.1.dmg


-install Qt in i.e. ~/Devel/Qt5.11.1SDK

(if You are going to use Qt newer than 5.5.1 - You need also address lacking of QtWebKit/QtWebKitWidgets in Qt newer than 5.5.1. I'm dealing with this by using Qt5.5.1 QtWebKit & QtWebKitWidgets binaries in Qt5.11.1.
To do this You may simple copy QtWebKit/QtWebKitWidgets
related files from <libs>, <mkspecs/modules> and <qml> to relevant dirs in Qt5.11.1 install.)


-clone MythTV sources

mkdir -p ~/Devel

cd ~/Devel

git clone https://github.com/MythTV/mythtv.git

cd ~/Devel/mythtv

git clone https://github.com/MythTV/packaging.git


-run script

osx-packager-qtsdk.pl -qtsdk ~/Devel/Qt5.11.1SDK/5.11.1/clang_64 -verbose -gitdir ~/Devel/mythtv -force




<b>3) Troubleshooting:</b>



Q: Script can't download some of source archives.

A: It is important to use exactly versions delared in script as those versions allows to successfuly build.
Try find missing source archives maually and put them into ~/Devel/.osx-packager/src with filename exactly script tries to download.
It is important that given source archive is archive of subdir named exactly as archive name.
Example: fftw3f-3.3.4.tar.bz2 should be archive of <fftw3f-3.3.4> dir containing fftw sources.


Q: Build process complains about missing QuickTime framework at linking time

A: Download https://github.com/phracker/MacOSX-SDKs/releases/tag/MacOSX10.11.sdk
Solution1:
1.Place the "MacOSX10.11.sdk" folder in /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs
2.Set Base SDK to "OS X 10.11" for the again target in the Xcode project settings

Solution2:
Symlink MacOSX10.11.sdk FrameworksQuickTime.framework to MacOSX SDK used by Xcode:
sudo ln -sf /Users/piotro/Devel/MacOSX10.11.sdk/System/Library/Frameworks/QuickTime.framework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/FrameworksQuickTime.framework

Happy compiling!

