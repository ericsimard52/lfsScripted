# lfsScripted
A scripted installation interface for Linux From Scratch
lfsScripted provides a console interface to compile LFS.
Compilation instruction are sourced from files in /etc/pkm/{package}/
It provides a tmpToolChain mode to build the temporary toolchain.
This is by no means a fully automated tool. You still need to follow the instruction for LFS. 
This tool is good to build the tmp  toolchain and the base system.
I am now working on a separate shell scripts to use as a package manager.
I will upload to a new git when the system is online.

## To Install
 - Clone or download this repo in /root/pkgManager of your LFS partition.
 - Copy directory etc/pkm to /etc
 - Create directory: /var/log/pkm
That's it, your ready to use it.

## Usage
#### preppkg: 
	Will ask you which package, it will then search /sources for matching package.
	You can provide only a partial input, it will then request confirmation on similar package found in /sources. 
	Warning: It will not make a difference bbetween packages and patches. 
	Review the file carefully before confirming a package.
#### loadpkg:
	Will ask which package to load. it will then search /etc/pkm for a match. You can provide partial input.
#### unpack
	Unpack the currently loaded package.
#### preconfig
	Run pre-config script for current package.
#### config
	Run config script.
#### compile
	Run compile script.
#### check
	Run check script. Confirmation is needed to continue to allow you to review check results.
#### preinstall
	Run preinstall script.
#### install
	Run install script. Remember to install to $FAKEROOT/$sdn.
	If you choose NOT to install in fakeroot, using implement will cause an error.
	You can still you preimplement and postimplement to provide instruction after installation.
#### preimplement
	Run pre-implement script.
#### implement
	Move package out of fakeroot and recorded file in log.
#### postimplement
	Run post-implement script.
#### cleanup
	Removes sources and fakeroot files.
#### autoinstall
	Checks all scripts file in /etc/pkm and execute the one with instruction.
	If bypassImplement=0 in conf file, implement function will not be called.
	Cleanup is called at the end after postimplement.
	Request host backup function is called after cleanup.
#### unload
	Unload currently loaded packaged and reset default values.
#### dump env
	Print outs environment variables. Good for debug.
#### backup
	Sets the flags to request a host backup.

## How to implement automated backup on the host system?
	I have to make the script more portable and then I will add it to this repo.
	In short, create a backup script on the host system.
	Setup iwatch or inotify to detect file creation: /root/pkgManager/backupNow
	When the file is detected, execute backup, then remove /root/pkgManager/backupNow
	This command line can be used to backup (You would need to adjust the paths and filename):
```shell
tar -cvf /root/LFS/LFS.tar --one-file-system --exclude-backups --exclude=/root/LFS/Disk/{dev,run,sys,proc}  /root/LFS/Disk/
```
