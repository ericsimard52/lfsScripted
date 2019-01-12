# lfs_pkm
LFS installation scripts.

1. Clone this repo in your home directory.
2. edit pkm.sh there is 2 variable to set at the top.
3. edit etc/pkm.conf
4. Execute pkm.sh

Note, keep this isolated in its own directory. a similar structure to root directory is established for convenience.

When pkm.sh is started, it proceed with reading the config file and export MAKEFLAGS.
After the configuration is loaded, we do a startup check.
- Check $LFS mount point exists, if not create it.
- Go through partitionName
  - If swap, activate it.
  - If mount point does not exists, create it in $LFS/mountPoint
  - Mount the partition
- Check if sd (source directory) exists, if not create it.
- Check if we have a wget.list, if not we fetch it from linucfromscratch.org
- Same for md5sum
- We then check each pkg, if we don't have it, download it.
- Now we do our md5sum check
- Check if $LFS/tools exists if not create it
- Check for $LFS/tool -> / link
- Check if we have lfs group <-- group and user setting are hardcoded for now.
- Check if we have lfs user
- Create group and user if needed and set password
- We fix ownership of source directory $LFS & $LFS/tools
- Check kfs user environment.
  - create .bash_profile if not exists
  - create .bashrc if not exists
- Log subsystem is started.
- Prompt is given to user.

Commands: (may not all be fully implemented)
  - listcommands
    Will ask wich command, they represent config script, it will then print config script to stdout
  - fetch (Not working)
  - unpack
    Unpack the loaded package
  - depcheck
    source script. Include in this script logic to check for requirement.
  - preconfig
    source script. Code to be run before configuring the script.
    In case where the package requires a build directory, this is the last script to be run outside of that build directory
  - config
    source script. Here we run configuration code. Runs inside build directory if set.
  - compile
    source script. Compile the code.
  - check
    source script. Run checks and test on compiled code.
  - preinstall
    source script. run some code before installing
  - install
    source script. Run installation.
    When building the temporary tool chains, implementation need to be bypassed, we do not use a fakeroot yet.
  - preimplement
    source script executed after install
  - implement
    Not used when building temp toolchain. Used when we install in fakeroot.
    This is a hardcoded function that will implement a pkg install in fakeroot and logs file and directory.
  - postimplement
    To be ran after implement. Carefull any file creation in this section will not be logged.
  - autoinstall
    Run all required script in order.
  - listtask
    list task required by a package.
  - cleanup
    Cleanup source and fakeroot. Does not remove downloaded packages, just the uncompressed source file.
    Ask for confirmation before deleting source or fakeroot
  - preppkg
    Prepare a skeleton in /etc for a new package
  - loadpkg
    load a package in memory
  - unloadpkg
    unload packages and reset variable
  - backup
    Request host back in temp toolchain mode.
    A specific section for this will come.
  - dumpenv
    Dump environment variable
  - debug
    set debug level 0, 1, 2
  - reload
    reload config file
  - quit
    quit program.
