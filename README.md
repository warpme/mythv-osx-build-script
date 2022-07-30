# mythv-osx-build-script

Script allows to build current mythtv-master (tested on  pre-33, r742) on vanilla MacOS
(only Xcode required; tested on macOS 11.6.8 with Xcode 12.4 12D4e)

It is based on excellent work of:

Copyright (c) 2012-2014 Jean-Yves Avenard

Jeremiah Morris <jm@whpress.com>



Goal for my work on this scipt was 2-fold:

1.build with prebuild Qt binaries (tested 5.15.2)

2.full automated build of working Mythfrontend.app



When compared to original osx-packager-qtsdk from MythTV packaging repo, script has following chnges:

-support only for myth-v32 (not tested) and mayth-master (tested).

-remove code dealing with mythtv git sources (script assumes user already has directory with myth code for compilation).




<b>1) Preliminaries:</b>



-macOS XCode 12 (tested on Xcode 12.4 12D4e)

-installed prebuild Qt binaries (tested on Qt5.15.2)




<b>2) Building mythtv:</b>



-download Qt binaries from Qt by Qt-online app

-install Qt in i.e. ~/Devel/Qt5.15.2SDK

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

osx-packager-qtsdk.pl -qtsdk ~/Devel/Qt5.15.2SDK/5.15.2/clang_64 -verbose -gitdir ~/Devel/mythtv -force




<b>3) Troubleshooting:</b>



Q: Script can't download some of source archives.

A: It is important to use exactly versions delared in script as those versions allows to successfuly build.
Try find missing source archives maually and put them into ~/Devel/.osx-packager/src with filename exactly script tries to download.
It is important that given source archive is archive of subdir named exactly as archive name.
Example: fftw3f-3.3.4.tar.bz2 should be archive of <fftw3f-3.3.4> dir containing fftw sources.


Happy compiling!

