ANDARIUMMAX  v0.1  -  Made by Claude Strife - X
======================================================================
Measures how fast Android runs inside Andarium on your iPhone, and tunes
it. Nothing here changes Andarium itself.

FIRST TIME
 Double-click BUILD.bat. It checks Rust, gets adb, builds with live
 progress and opens AndariumMax.exe. After that, just open AndariumMax.exe.

ON THE IPHONE (once per Android start)
 1. Android Settings > About phone > tap Build number 7 times.
 2. Android Settings > System > Developer options > USB debugging: on.
 3. Andarium's Settings > Developer > ADB over network: on. Allow Local Network.
 4. Same Wi-Fi as this PC. IP address: iOS Settings > Wi-Fi > (i).
 Keep Andarium on screen and the phone unlocked during a test.

IN ANDARIUMMAX
 1  Connect - type the iPhone's IP, then tap Allow on Android.
 3  Quick benchmark - 5 cold launches + 60 s of frames. Name each run.
 4  Sustained test - 10 minutes: does it slow down as the phone heats?
 5  Speed-compile an app - can make it start faster. 6 undoes it.
 8  Compare two saved results - shows the real % change.
 Results are saved in the results folder.

WHAT IS IN THIS FOLDER
 BUILD.bat, AndariumMax.exe   the tool
 Kernarium\                   the Andarium source (branch performance-fork)
 Kernarium\fork\              the fork's documents, tool source, Mac script
 The iPhone app itself can only be built on a Mac: see
 Kernarium\fork\BUILD_INSTRUCTIONS.md.
