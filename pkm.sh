#!/bin/bash

declare buildTmpMode=1 # Set to 0 to build tmp tool chain by default
declare lfsScripted="/root/pkgManager" # Set to lfsScripted absolute path.

declare LFS # Used in buildTmpMode
declare configFile
declare sd
declare tf
declare sdn
declare sdnConf
declare ext
declare unpackCmd
declare hasBuildDir
declare buildDir
declare MAKEFLAGS
declare banner
declare ld
declare bypassImplement
declare isImplemented=1

###
# There is too many log files. Implement debug level to reduce.
# Log files
# 0 = Default; 1 = Unpacking; 2 = Preconfig; 3 = Config; 4 = Compile; 5 = Check;
# 6 = PreInstall; 7 = Install; 8 = PreImplement; 9 = Implement; 10 = PostImplement
###
declare -a lf=() # Will contain a list of all log files.
declare FAKEROOT
declare CURSTATE=0 # Set to 1 to exit program succesfully
declare confBase

# Config files
declare genConfigFile
declare preconfigCmdFile
declare configCmdFile
declare compileCmdFile
declare checkCmdFile
declare preInstallCmdFile
declare installCmdFile
declare preImplementCmdFile
declare postImplementCmdFile
declare -a cmdFileList
declare -a autoInstallCmdList

###
# Switch between mode to build tmp tool chain and mode to build system
###

function switchMode {
    if [[ $buildTmpMode > 0 ]]; then # Turning build tmp tool chain mode on
        buildTmpMode=0
        setConfigFile
        readConfig
    else
        buildTmpMode=1
        setConfigFile
        readConfig
    fi
}

function setConfigFile {
    if [[ $buildTmpMode == 0 ]]; then # Build tmp tool chain mode on
        configFile="$lfsScripted/etc/pkm/tmpToolChain/pkm.conf"
    else
        configFile="/etc/pkm/pkm.conf" #We assume chroot environment here, otherwise prepend $lfsScripted to use local config
    fi
    log "INFO: Config file: $configFile" t
}

function readConfig {
    if [ ! -f $configFile ]; then
        touch $configFile
    fi
    while read -r line; do
        IFS=':' read -ra PARAM <<< "$line"
        case "${PARAM[0]}" in
            sd) sd=${PARAM[1]};;
            MAKEFLAGS) MAKEFLAGS=${PARAM[1]};;
            FAKEROOT) FAKEROOT=${PARAM[1]};;
            bypassImplement) bypassImplement=${PARAM[1]};;
            LFS) lfs=${PARAM[1]};;
            confBase) confBase=${PARAM[1]};;
            *) echo "Unknow params: ${PARAM[0]}";;
        esac
        unset IFS
    done < $configFile

}

function unloadPkg {
    unset -v pkg sdnConf tf sdn hasBuildDir buildDir ld ext unpackCmd banner genConfigFile preconfigCmdFile configCmdFile compileCmdFile checkCmdFile preInstallCmdFile installCmdFile preImplementCmdFile postImplementCmdFile cmdFileList preconfigCmd configCmd compileCmd checkCmd preInstallCmd installCmd preImplementCmd postImplementCmd autoInstallCmdList lf
    isImplemented=1
    readConfig
}

###
# Enumerate through commans stores in commands array
# all does not work as intended
###
function listCommands {
    declare cmd
    COLOR="\e[32]"
    promptUser "Which command?"
    read x
    case $x in
        preconfig | all)
            c="cat $preConfigCmdFile"
            eval $c | tee -a 2>> $ld/${lf[0]}
            ;;
        config | all)
            i=0
            ;;
        compile | all)
            i=0
            ;;
        check | all)
            i=0
            ;;
        preInstall | all)
            i=0
            ;;
        install | all)
            i=0
            ;;
        preImplement | all)
            i=0
            ;;
        postImplement | all)
            i=0
            ;;

    esac


}

function setBanner {
    #log "INFO: Setting up banner." true
    #banner="Installing $sdn\nRun the following commands:\n"
    banner=""
}

# Log always logs to default log file
# pass a second param to display to stdout also
function log {
    declare COLOR
    declare MSG
    declare M
    MSGEND=" \e[0m" ## Clear all formatting
    IFS=':' read -ra PARTS <<< $1
    case "${PARTS[0]}" in
        INFO)
            COLOR="\e[34m"
            M=$1
            ;;
        WARNING)
            COLOR="\e[33m"
            M=$1
            ;;
        ERROR)
            COLOR="\e[91m"
            M=$1
            ;;
        FATAL)
            COLOR="\e[91m"
            M=$1
            ;;
    esac
    MSG=$COLOR$M$MSGEND
    if [[ $2 != "" ]]; then
        if [[ ${lf[0]} == "" ]]; then
            echo -e "NOLOG-"$MSG
            return
        fi
        echo $M >> $ld/${lf[0]}
        echo -e $MSG
        return
    fi
    if [[ ${lf[0]} == "" ]]; then
        echo -e "NOLOG-"$MSG
    fi
    echo $M >> $ld/${lf[0]}
    unset IFS
}

function promptUser {
    COLOR="\e[37m"
    echo -en $COLOR$1" : \e[0m"
}

function unpack {
    log "INFO:Unpacking source code $tf" true

    if [ ! -f $sd/$tf ]; then
        log "FATAL:$tf not found, quitting" true
        exit 1
    fi

    log "INFO:Running Cmd: $unpackCmd" true
    log "file:$ld/${lf[1]}"
    pushd $sd > /dev/null
    if [[ $? > 0 ]]; then
        log "FATAL: pushd to $sd failed." true
        exit 1
    fi

    eval $unpackCmd >> $ld/${lf[1]}
    if [ $hasBuildDir == 0 ]; then
        log "INFO:Creating build directory" true
        mkdir -v $sd/$sdn/build
    fi

    popd > /dev/null 2>&1
    log "Done" true
}

function requestHostBackup {
    declare tag
    if [[ "$1" == "" ]]; then
        promptUser "Backup Tag: "
        read tag
    else
        tag=$1
    fi

    cat > /root/pkgManager/backupNow <<EOF
name:$tag
EOF
    promptUser "I set the back flag, no inotify install here yet, Press enter to continue."
    read u
    if [ -f /root/pkgManager/backupNow ]; then
        promptUser "WARN: back flag still present are you sure? Y/n"
        read v
        case v in
            [Nn])
                promptUser "There is no check after this, make sure you are ready. Press enter to continue."
                read u
                rm -v /root/pkgManager/backupNow
                ;;
            [Yy]|*)
                rm -v /root/pkgManager/backupNow
                ;;
        esac
    fi
}

function autoInstall {
    log "INFO: Will be running the following tasks:"
    i=0
    while [[ $i < ${#autoInstallCmdList[@]} ]]; do
        echo "${autoInstallCmdList[$i]}"
        ((i++))
    done
    promptUser "Do you want to start now?"
    read y
    case $y in
        [nN])
            return
            ;;
        [yY]|*)
            runAutoInstall
            ;;
    esac
}

function runAutoInstall {
    promptUser "Do you want to request backup from the host? Y/n"
    read u
    case $u in
        [nN])
            return 0
            ;;
        [yY]|*)
            requestHostBackup "PRE-$sdn"
            ;;
    esac

    i=0
    while [[ $i < ${#autoInstallCmdList[@]} ]]; do
        f=${autoInstallCmdList[$i]}
        fbase=$(basename $f)
        echo "$fbase"
        if [ "$fbase" = "postImplement" ]; then
            if [[ $bypassImplement > 0 ]]; then
                log "INFO: Post Implement detected, running Implement first." true
                implementPkg
                isImplemented=0
            else
                log "INFO: Post Implement detected, and bypass Implement is active, proceeding." true
            fi
        fi
        log "INFO: Sourcing $f." true
        evalPrompt $fbase
        res=$?
        if [[ $res > 0 ]]; then
            log "ERROR: Error sourcing $f." true
            return $res
        fi
        if [ "$fbase" = "check" ]; then
            promptUser "Just finish checks, verify it. Do I keep going? Y/n"
            read t
            case $t in
                [Nn])
                    return 1
                    ;;
                [Yy]|*)
                    ((i++))
                    continue
                    ;;
            esac
        fi

        ((i++))
    done
    if [[ $isImplemented > 0 ]]; then
        log "INFO: Implementing pkg." t
        implementPkg
        isImplemented=0
    fi
    cleanup
    promptUser "Do you want to request backup from the host? Y/n"
    read u
    case $u in
        [nN])
            return 0
            ;;
        [yY]|*)
            requestHostBackup "POST-$sdn"
            ;;
    esac
    return 0
}

function sourceScript {
    c=$1
    log "INFO: Sourcing: $c" true
    source $c
    res=$?
    log "INFO: Sourced $c returned: $res" true
    return $res
}

function implementPkg {
    pushd $FAKEROOT/$sdn > /dev/null
    if [[ $? > 0 ]]; then
        log "FATAL: pushd to $FAKEROOT/$sdn failed." true
        exit 1
    fi

    log "INFO: Setting file in system" true
    log "file:$ld/${lf[9]}"
    tar cvf - . | (cd / ; tar vxf - ) |tee -a $ld/${lf[9]} 2>> $ld/${lf[0]}
    popd > /dev/null 2>&1
}

function cleanup {
    log "INFO: Cleaning up source file" true
    pushd $sd > /dev/null
    if [[ $? > 0 ]]; then
        log "FATAL: pushd to $sd failed." true
        exit 1
    fi

    rm -fr $sdn | tee -a $ld/${lf[1]} 2>> $ld/${lf[0]}
    popd > /dev/null 2>&1

    if [[ $buildTmpMode == 0 ]]; then
        return
    fi
    promptUser "Remove Fakeroot Files? y/N"
    read x
    case $x in
        [yY])
            log "INFO: Removing fakeroot." true
            rm -fvr $FAKEROOT/$sdn
            ;;
        [nN] | *)
            log "INFO: Leaving fakeroot in place." true
            ;;
    esac

}

function setLF {
    log "INFO: Setting up lf." true
    if [ "$sdn" == "" ]; then
        log "ERROR: sdn is not set." true
        return
    fi
    lf=(
        "$sdn.log.org"
        "$sdn.unpack.org"
        "$sdn.preconfig.org"
        "$sdn.config.org"
        "$sdn.compile.org"
        "$sdn.check.org"
        "$sdn.preinstall.org"
        "$sdn.install.org"
        "$sdn.preimplement.org"
        "$sdn.implement.org"
        "$sdn.postimplement.org"
    )
}

function setCmdFileList {
    log "INFO: Setting up command files list." true
    if [ "$sdn" == "" ]; then
        log "ERROR: sdn is not set." true
        return
    fi
    if [ "$sdnConf" == "" ]; then
        log "ERROR: sdnConf not set." true
        return
    fi

    preconfigCmdFile=$sdnConf/preconfig
    configCmdFile=$sdnConf/config
    compileCmdFile=$sdnConf/compile
    checkCmdFile=$sdnConf/check
    preInstallCmdFile=$sdnConf/preinstall
    installCmdFile=$sdnConf/install
    preImplementCmdFile=$sdnConf/preimplement
    postImplementCmdFile=$sdnConf/postimplement
    cmdFileList=(
        $preconfigCmdFile
        $configCmdFile
        $compileCmdFile
        $checkCmdFile
        $preInstallCmdFile
        $installCmdFile
        $preImplementCmdFile
        $postImplementCmdFile
    )

}

###
# Preparation of a new package
###
function prepPkg {
    unloadPkg

    promptUser "Package name?"
    read -e pkg

    # If we can't file the package (source tar), we do a search for the term provided by the user.
    if [ ! -f $sd/$pkg ]; then
        log "ERROR: Package not found in $sd." true
        log "INFO: Searching for $pkg*." true
        declare -a foundFiles
        for file in `find $sd -maxdepth 1 -type f -iname $pkg*.*`; do
            promptUser "FoundFiles: $file\n Use it? Y/n"
            read u
            case $u in
                [nN])
                    continue
                    ;;
                [yY]|*)
                    log "INFO: Using: $file" true
                    pkg=$(basename $file)
                    if [ ! -f $sd/$pkg ]; then
                        log "FATAL: Could not find $pkg after finding it????" true
                        return
                    fi
                    break
                    ;;
            esac
        done
        if [ ! -f $sd/$pkg ]; then
            log "FATAL: No package found for $pkg." true
            return
        fi

    fi
    tf=$pkg
    sdn="${tf%.tar.*}" # Get the filename
    sdnConf="$confBase/$sdn"
    setCmdFileList

    ## Creating log directory
    ld="/var/log/pkm/$sdn"
    log "INFO: Checking log directory: $ld" true
    if [ ! -d "$ld" ]; then
        log "INFO: Creating log directory" true
        md="mkdir -vp $ld"
        eval $md
        if [[ $? > 0 ]]; then
            log "FATAL: Error creating log directory" true
            return 1
        fi
    fi

    setLF

    if [ -d $sdnConf ]; then
        log "WARNING: Config Directory exists. Previous configuration file will be left intact." true
    else
        md="mkdir -vp $sdnConf/"
        log "INFO: Creating package configuration directory: $md" true
        eval $md | tee -a $ld/${lf[0]} 2>> $ld/${lf[0]}
        if [[ $? > 0 ]]; then
            evalError $cmd
            return
        fi
        log "INFO: $sdnConf created" true
    fi
    echo -n "Does the package requires a build directory? y/N "
    read d
    case $d in
        [yY])
            log "Adjusting script config for build directory" true
            buildDir="$sd/$sdn/build"
            hasBuildDir=0
            ;;
        *)
            buildDir="$sd/$sdn"
            hasBuildDir=1
            ;;
    esac

    log "INFO: Creating general config file." true
    conf="tf:$tf\nsdn:$sdn\nhasBuildDir:$hasBuildDir"
    genConfigFile="$sdnConf/$sdn.conf"
    ct="echo -e \"$conf\" > $genConfigFile"
    eval $ct | tee -a $ld/${lf[0]} 2>> $ld/${lf[0]}
    if [[ $? > 0 ]]; then
        evalError $ct
        return
    fi

    cmdArrLen=${#cmdFileList[@]}
    log "INFO: Installing configuration files." true
    i=0
    while [ $i -lt $cmdArrLen ]; do
        fn=${cmdFileList[$i]}
        echo $fn
        if [ -f $fn ]; then
            log "WARNING: Old config file present." true
            ((i++))
            continue
        fi
        log "INFO: Creating $fn"
        tc="touch $fn && chmod +x $fn"
        eval $tc | tee -a $ld/${lf[0]} 2>> $ld/${lf[0]}
        if [[ $? > 0 ]]; then
            evalError $tc
            return
        fi
        ((i++))
    done

    log "INFO: Configuration created." true

}

function loadPkg {
    if [[ ! "$pkg" == "" ]]; then
        log "INFO: Unloading previous package from memory." true
        unloadPkg
    fi
    promptUser "Which package?"
    read pkg
    if [[ "$pkg" == "" ]]; then
        echo "Empty package provided..."
        return
    fi
    if [ ! -d $confBase/$pkg ]; then
        echo "Configuration not found for $pkg"
        declare -a foundFiles
        for file in `find $confBase -maxdepth 1 -type d -iname $pkg*`; do
            promptUser "FoundFiles: $file\n Use it? Y/n"
            read u
            case $u in
                [nN])
                    continue
                    ;;
                [yY]|*)
                    log "INFO: Using: $file" true
                    pkg=$(basename $file)
                    if [ ! -d $confBase/$pkg ]; then
                        log "FATAL: Could not find $pkg after finding it????" true
                        return
                    fi
                    ;;
            esac
        done
        if [ ! -d $confBase/$pkg ]; then
            log "FATAL: No package found for $pkg." true
            return
        fi
    fi
    sdnConf=$confBase/$pkg
    genConfigFile="$sdnConf/$pkg.conf"
    if [ ! -f $genConfigFile ]; then
        echo "Package general config file missing"
        return
    fi

    echo "Reading config file into variables"
    while read -r line; do
        IFS=':' read -ra PARAM <<< "$line"
        case "${PARAM[0]}" in
            tf) tf=${PARAM[1]};;
            sdn) sdn=${PARAM[1]};;
            sd) sd=${PARAM[1]};;
            hasBuildDir) hasBuildDir=${PARAM[1]};;
            tasks)
                IFS=',' read -ra TASK <<< "${PARAM[1]}"
                x=0
                while [[ $x < ${#TASK[@]} ]]; do
                    autoInstallCmdList+=(${TASK[$x]})
                    ((x++))
                done
                IFS=':'
                ;;
            *) echo "Unknow params: ${PARAMS[1]}";;
        esac
        unset IFS
    done < $genConfigFile


    echo "Check if source package exists"
    # Check if source package exists
    if [ ! -f $sd/$tf ]; then
        echo "Package $tf not found in source $sd"
        return
    fi

    ext="${tf##*.}"
    sdnConf="$confBase/$sdn"
    setCmdFileList
    echo "hbd: $hasBuildDir"
    if [ $hasBuildDir -lt 1 ]; then
        buildDir=$sd/$sdn/build
    else
        buildDir=$sd/$sdn
    fi

    ld="/var/log/pkm/$sdn"
    echo "Checking log directorie: $ld"
    if [ ! -d "$ld" ]; then
        log "WARNING: Package directory not found, creating." true
        mkdir $ld
    fi
    setLF

    # Adjusting the unpack commands
    log "INFO: Adjusting unpack command." true
    if [[ "$ext" == "xz" ]]; then
        unpackCmd="tar xvf $tf"
    elif [[ "$ext" == "gz" ]]; then
        unpackCmd="tar xvfz $tf"
    elif [[ "$ext" == "bz2" ]]; then
        unpackCmd="tar xvfj $tf"
    else
        log "FATAL: Unknown package unpack method." true
        return
    fi

    log "INFO: Loading commands." true
    setBanner
}

function dumpEnv {
    printf "buildTmpMode: $buildTmpMode
sd: $sd
tf: $tf
sdnConf: $sdnConf
ext: $ext
hasBuildDir: $hasBuildDir
MAKEFLAGS: $MAKEFLAGS
buildDir: $buildDir
LFS: $LFS
configFile: $configFile
confBase: $confBase\n"
}

function listTask {
    i=0
    while [[ $i < ${#autoInstallCmdList[@]} ]]; do
        echo -n "${autoInstallCmdList[$i]}, "
        ((i++))
    done
    echo ""
}
function evalError {
    log "ERROR: Error during eval: $1" true
}

function evalPrompt {
    case $1 in
        listcommands)
            listCommands
            ;;
        unpack)
            unpack
            ;;
        preconfig)
            if [ $hasBuildDir -lt 1 ]; then
                pushd $sd/$sdn > /dev/null
            else
                pushd $buildDir >/dev/null
            fi
            if [[ $? > 0 ]]; then
                log "FATAL: pushd to $buildDir failed." true
                exit 1
            fi
            sourceScript "${preconfigCmdFile}"
            log "INFO: Running pre-config scripts" true
            log "file:$ld/${lf[2]}"
            popd > /dev/null 2>&1
            ;;
        config)
            log "INFO: Running config scripts" true
            log "file:$ld/${lf[3]}"
            pushd $buildDir
            if [[ $? > 0 ]]; then
                log "FATAL: pushd to $buildDir failed." true
                exit 1
            fi
            sourceScript "${configCmdFile}"
            popd > /dev/null 2>&1
            ;;
        compile)
            log "INFO: Running compile scripts" true
            log "file:$ld/${lf[4]}"
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "FATAL: pushd to $buildDir failed." true
                exit 1
            fi
            sourceScript "${compileCmdFile}"
            popd > /dev/null 2>&1
            ;;
        check)
            log "INFO: Running check scripts" true
            log "file:$ld/${lf[5]}"
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "FATAL: pushd to $buildDir failed." true
                exit 1
            fi
            sourceScript "${checkCmdFile}"
            popd > /dev/null 2>&1
            ;;
        preinstall)
            log "INFO: Running PreInstall scripts" true
            log "file:$ld/${lf[6]}"
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "FATAL: pushd to $buildDir failed." true
                exit 1
            fi
            sourceScript "${preInstallCmdFile}"
            popd > /dev/null 2>&1
            ;;
        install)
            log "INFO: Running install scripts" true
            log "INFO: FakeRoot: $FAKEROOT/$sdn" true
            log "file:$ld/${lf[7]}"
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "FATAL: pushd to $buildDir failed." true
                exit 1
            fi
            sourceScript "${installCmdFile}"
            popd > /dev/null 2>&1
            ;;
        preimplement)
            log "INFO: Running preImplement scripts" true
            log "file:$ld/${lf[8]}"
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "FATAL: pushd to $buildDir failed." true
                exit 1
            fi
            sourceScript "${preImplementCmdFile}"
            popd > /dev/null 2>&1
            ;;
        implement)
            if [[ $buildTmpMode == 0 ]]; then
                log "ERROR: Implement is disabled in building tmp toolchain mode." t
                return
            fi
            implementPkg
            ;;
        postimplement)
            log "INFO Running PostImplement scripts" true
            log "file:$ld/${lf[10]}"
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "FATAL: pushd to $buildDir failed." true
                exit 1
            fi
            sourceScript "${postImplementCmdFile}"
            popd > /dev/null 2>&1
            ;;
        autoinstall)
            autoInstall
            ;;
        listtask)
            listTask
            ;;
        cleanup)
            cleanup
            ;;
        preppkg)
            prepPkg
            ;;
        loadpkg)
            loadPkg
            ;;
        unloadpkg)
            unloadPkg
            ;;
        backup)
            requestHostBackup
            ;;
        dumpenv)
            dumpEnv
            ;;
        switchmode)
            switchMode
            ;;
        reload)
            readConfig
            ;;
        quit)
            echo "Quitting"
            CURSTATE=1
            ;;
        *)
            echo "Unknown command"
            ;;
    esac

}

function prompt {
    while [[ $CURSTATE == [0] ]]; do
        echo -e $banner
        promptUser "Input."
        read -e command
        evalPrompt $command
    done
}


setConfigFile
readConfig
export MAKEFLAGS
prompt
