# Syncthing Power Manager

Tries to wake up a server to let Syncthing update both before and after the user works on the computer.

## Features

- Shows itself as an icon in the system tray, changing colors depending on the sync status.
- Uses WOL (Wake on LAN) to contact the chosen server.
- Automatically triggers a Syncthing update whenever the display shuts down, the user presses the power save button, or the computer resumes from a power save.
- Monitors the computer's power saving timeouts and adapts to them. It even handles the common Windows glitch where the display randomly wakes up for no apparent reason.
- Advanced action logging with adjustable levels from 1 to 4:
  1. System & Errors (`#Log_Error`)
  2. Warnings (`#Log_Warning`)
  3. Informative / Actions (`#Log_Info` - *Recommended*)
  4. Highly Detailed / Debug (`#Log_Detail`)

## Requirements Running the Software

- Windows 10 or 11 (no other versions have been tested).
- An installed and working instance of Syncthing.
- A configured file server with Syncthing installed that uses power-saving mode and is configured to react to WOL.
- Very low hardware requirements (runs lightweight background supervision).

## Requirements Compiling the Source Code

- Full version of **PureBasic** 6+ (source code written using version 6.40).
- Open **SPM.pbp** in the PureBasic IDE.
- Press **F5** to compile and run (Requires *Thread-Safe* option enabled).

## How to Install

There is no installer. Just place the compiled `.exe` file in a folder of your choice.

If you want the program to autostart with Windows:

1. Press `Windows + R` to open the Run dialog.
2. Type `shell:startup` and press OK.
3. Place a shortcut to your `.exe` file in that folder.

The software will automatically open the Preferences window upon its very first launch, allowing you to configure your network settings and the Syncthing API. 

*Note: Depending on your router and network setup, the network Lookup function might not immediately find all machines. If the server is missing, try waking it up manually before running the lookup again.*

## Download

If you just want to run the program without installing PureBasic, go to the **Releases** section on the right side of this page and download the latest version.
