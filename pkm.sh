#!/bin/bash

#
declare devBase="/home/tech/Git/lfsScripted"
declare configFile="$devBase/etc/pkm.conf"
declare sd td sdn sdnConf pkg ext hasBuildDir buildDir confBase wgetUrl LFS lfsUserHome
declare -a partitionDev partitionName partitionMount partitionFs
declare unpackCmd
declare MAKEFLAGS
declare DEBUG=0 # 0=OFF, 1= ON, but not to stdout, send all debug to log file. 2= send to stdout and logfile
declare genLogFile pkgLogFile impLogFile errLogFile
declare genLogFD pkgLogFD impLogFD errLogFD #File descriptor input only
declare bypassImplement=0 # Implementation bypassed in temp toolchain, we do not use fakeroot.
declare isImplemented=1 # This changes to 0 when implementation is done.
declare CURSTATE=0 # Set to 1 to exit program succesfully

# Config files
declare genConfigFile depcheckCmdFile preconfigCmdFile configCmdFile compileCmdFile checkCmdFile
declare preInstallCmdFile installCmdFile preImplementCmdFile postImplementCmdFile
declare -a cmdFileList
declare -a autoInstallCmdList

function singleton {
    if [ -f $devBase/var/run/pkm/pkm.lock ]; then
        log "NULL|FATAL|Pkm is already running or has not quit properly, in that case, remove $devBase/var/run/pkm/pkm.lock" t
        return 1
    fi
    processCmd "sudo -u pkm touch $devBase/var/run/pkm/pkm.lock"
}

function startLog {
    if [ ! -f $genLogFile ]; then
        log "NULL|INFO|Creating $genLogFile" t
        sudo -u pkm touch $genLogFile
        sudo -u pkm chmod 666 -v $genLogFile
    fi
    if [ ! -f $pkgLogFile ]; then
        log "NULL|INFO|Creating $pkgLogFile" t
        sudo -u pkm touch $pkgLogFile
        sudo -u pkm chmod 666 -v $pkgLogFile
    fi
    if [ ! -f $impLogFile ]; then
        log "NULL|INFO|Creating $impLogFile" t
        sudo -u pkm touch $impLogFile
        sudo -u pkm chmod 666 -v $impLogFile
    fi
    if [ ! -f $errLogFile ]; then
        log "NULL|INFO|Creating $errLogFile" t
        sudo -u pkm touch $errLogFile
        sudo -u pkm chmod 666 -v $errLogFile
    fi
    log "NULL|INFO|Creating file descriptor for logs" t t
    exec {genLogFD}>$genLogFile
    exec {pkgLogFD}>$pkgLogFile
    exec {impLogFD}>$impLogFile
    exec {errLogFD}>$errLogFile
}

###
# Read config file stored in $configFile
###
function readConfig {
    log "NULL|INFO|Reading configuration file." t
    if [ ! -f $configFile ]; then
        log "NULL|ERROR|Configuration file: $configfile is missing." t
        return 1
    fi
    while read -r line; do
        IFS=':' read -ra PARAM <<< "$line"
        case "${PARAM[0]}" in
            debug)
                DEBUG=${PARAM[1]}
                if [[ $DEBUG > 0 ]];then
                    log "NULL|INFO|Set param DEBUG:$DEBUG" t
                fi
                ;;
            sd)
                sd=${PARAM[1]}
                log "NULL|INFO|Set param sd:$sd" t t
                ;;
            confBase)
                confBase=${PARAM[1]}
                log "NULL|INFO|Set param confBase:$confBase" t t
                ;;
            MAKEFLAGS)
                MAKEFLAGS=${PARAM[1]}
                log "NULL|INFO|Set param MAKEFLAGS:$MAKEFLAGS" t t
                ;;
            bypassImplement)
                bypassImplement=${PARAM[1]}
                log "NULL|INFO|Set param bypassImplement:$bypassImplement" t t
                ;;
            genLog)
                genLogFile=${PARAM[1]}
                log "NULL|INFO|Set param genLogFile:$genLogFile" t t
                ;;
            pkgLog)
                pkgLogFile=${PARAM[1]}
                log "NULL|INFO|Set param pkgLogFile:$pkgLogFile" t t
                ;;
            errLog)
                errLogFile=${PARAM[1]}
                log "NULL|INFO|Set param errLogFile:$errLogFile" t t
                ;;
            impLog)
                impLogFile=${PARAM[1]}
                log "NULL|INFO|Set param impLogFile:$impLogFile" t t
                ;;
            partitionDev)
                partitionDev=(${PARAM[1]})
                log "NULL|INFO|Set param partitionDev:$partitionDev" t t
                ;;
            partitionName)
                partitionName=(${PARAM[1]})
                log "NULL|INFO|Set param partitionName:$partitionName" t t
                ;;
            partitionMount)
                partitionMount=(${PARAM[1]})
                log "NULL|INFO|Set param partitionMount:$partitionMount" t t
                ;;
            partitionFs)
                partitionFs=(${PARAM[1]})
                log "NULL|INFO|Set param partitionFs:$partitionFs" t t
                ;;
            LFS)
                LFS=${PARAM[1]}
                log "NULL|INFO|Set param LFS:$LFS" t t
                ;;
            lfsUserHome)
                lfsUserHome=${PARAM[1]}
                log "NULL|INFO|Set param lfsUserHome:$lfsUserHome" t t
                ;;
            "#") continue;;
            *) continue;;
        esac
        unset IFS
    done < $configFile
    export MAKEFLAGS
    log "NULL|INFO|Done reading config file." t
}

function startupCheck {
    log "GEN|INFO|Checking environment." t
    log "GEN|INFO|Checking mountpoint." t t
    if [ ! -d $LFS ]; then
        log "GEN|ERROR|Mount point $LFS does not exist. Creating." t
        sudo mkdir -pv $LFS
    fi
    log "GEN|INFO|Mounting partitions." t
    x=0
    pl=${#partitionName[@]}
    log "GEN|INFO|Got $pl partition to mount." t t
    while [ $x -lt $pl ]; do
        pn=${partitionName[$x]}
        pm=${partitionMount[$x]}
        pd=${partitionDev[$x]}
        pf=${partitionFs[$x]}

        if [[ "$pn" = "swap" ]]; then
            log "GEN|INFO|Found swap partition, Ativating." t
            sudo /sbin/swapon -v $pd
            log "GEN|WARNING|Swap should be last to mount, if not, next partition will not be mounted." t
            break;
        fi

        if [ ! -d $LFS$pm ]; then
            log "GEN|WARNING|$LFS$pm does not exists, creating." t t
            sudo mkdir -pv $LFS$pm
        fi
        log "GEN|INFO|Mounting $pn $pd => $LFS$pm $pf" t t
        sudo mount -v -t $pf $pd $LFS$pm
        ((x++))
    done
    log "GEN|INFO|Done." t

    log "GEN|INFO|Checking if source directory $sd exists." t t
    if [ ! -d $sd ]; then
        log "GEN|WARNING|Source directory $sd does not exists, creating." t t
        sudo mkdir -vp $sd
        sudo chmod -v a+wt $sd
    fi
    log "GEN|INFO|Done." t

    log "GEN|INFO|Checking sources packages." t
    log "GEN|INFO|Do we have wget.list?" t t
    if [ ! -f $confBase/wget.list ]; then
        log "GEN|WARNING|wget.list not found, fetching." t t
        sudo wget  -O $confBase/wget.list -v "http://www.linuxfromscratch.org/lfs/view/stable/wget-list"
    fi
    log "GEN|INFO|Do we have md5sums?" t t
    if [ ! -f $confBase/md5sums ]; then
        log "GEN|WARNING|md5sums not found, fetching." t t
        sudo wget  -O $confBase/md5sums -v "http://www.linuxfromscratch.org/lfs/view/stable/md5sums"
    fi

    log "GEN|INFO|Checking source packages." t
    for line in `cat $confBase/wget.list`; do
        fn=$(basename $line)
        log "GEN|INFO|Checking for $fn" t t
        if [ ! -f $sd/$fn ]; then
            log "GEN|INFO|Not found, fetching." t t
            sudo wget -v $line -O $sd/$fn
        fi
    done
    log "GEN|INFO|Checking md5." t
    pushd $sd >/dev/null
    sudo md5sum -c $confBase/md5sums
    popd >/dev/null

    log "GEN|INFO|Checking $LFS/tools." t t
    if [ ! -d $LFS/tools ]; then
        log "GEN|WARNING|$LFS/tools does not exists, creating." t t
        sudo mkdir -pv $LFS/tools
    fi
    if [ ! -h /tools ]; then
        log "GEN|WARNING|/tools does not exists, creating." t t
        sudo ln -sv $LFS/tools /
    fi

    log "GEN|INFO|Checking LFS group & user." t
    grep -q lfs < /etc/group
    if [[ $? > 0 ]];then
        log "GEN|WARNING|lfs group not found. Fixing." t
        sudo groupadd lfs
    fi

    grep -q lfs < /etc/passwd
    if [[ $? > 0 ]];then
        log "GEN|WARNING|lfs user not found. Fixing." t
        sudo useradd -s /bin/bash -g lfs -m -k /dev/null lfs
            log "GEN|INFO|Set password for lfs user." t
            sudo passwd lfs
    fi

    ### I don't check because maybe a file was downloaded at a later date.
    ### This way we are sure permission are correct.
    log "GEN|INFO|Fixing ownership." t
    sudo chown -R lfs:lfs $LFS/tools
    sudo chown -R lfs:lfs $sd

    log "GEN|INFO|Checking lfs user environment." t
    sudo chmod o+w -R $lfsUserHome
    if [ ! -f $lfsUserHome/.bash_profile ]; then
        log "GEN|INFO|Creating bash_profile." t t
        sudo -u lfs echo "exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash" > $lfsUserHome/.bash_profile
        sudo chown -v lfs:lfs $lfsUserHome/.bash_profile
    fi

    if [ ! -f $lfsUserHome/.bashrc ]; then
        log "GEN|INFO|Creating .bashrc." t t
        brc="set +h
umast 022
LFS=$LFS
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/tools/bin:/bin:/usr/bin
export LFS LC_ALL LFS_TGT PATHLC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/tools/bin:/bin:/usr/bin
export LFS LC_ALL LFS_TGT PATH
"
        sudo -u lfs echo $brc > $lfsUserHome/.bashrc
    fi
    sudo chmod o-w -R $lfsUserHome
}

function checkInstalled {
    processCmd "command -v "$1
    if [[ $? > 0 ]]; then
        return 1
    fi
    return 0
}

function checkLibInstalled {
    sudo -u pkm sudo ldconfig -p | grep $1
    if [[ $? > 0 ]]; then
        return 1
    fi
    return 0
}

function getVersion {
    reqCmd="$1"
    log "GEN|INFO|Getting version of "$reqCmd t t
    ### I redirect 2>&1 because bzip2 returns its version through stderr
    ### I pipe to sed to remove empty lines, perl version start with one.
    cmdVersion=`$1 --version 2>&1  | sed '/^$/d' |head -n1 | egrep -o "([0-9]{1,}\.)+[0-9]{1,}"`
    if [[ $? > 0 ]]; then
        log "PKG|WARNING|Unable to fetch version, attempting another way." t t
        cmdVersion=`$1 -version 2>&1  | sed '/^$/d' |head -n1 | egrep -o "([0-9]{1,}\.)+[0-9]{1,}"`
        if [[ $? > 0 ]]; then
            log "PKG|ERROR|Could not find version for $1." t
            return 1
        fi
    fi
    log "PKG|INFO|Found version: $cmdVersion." t t
    log "GEN|INFO|Removing all non numeric character." t t
    cmdVersion=$(echo $cmdVersion | sed 's/[^0-9]*//g')
    log "GEN|INFO|cmdVersion: $cmdVersion." t t
    eval "$2=$cmdVersion"
    return $?
}

function vercomp {
    declare cp='>='; ## Default comparator if not provided
    if [[ $3 ]]; then
        cp=$3
    fi
    log  "GEN|INFO|Comparing version: $1 $cp $2" t t
    if [[ $1 == $2 ]]; then
        return 0
    fi
    local IFS=.
    local i installedVer=($1) neededVer=($2) iv nv
    ivCount=0
    nvCount=0
    nvPad=0
    ivPad=0
    for (( i=0; i<${#installedVer[@]}; i++ )); do
        iv=$iv${installedVer[$i]}
    done

    for (( i=0; i<${#neededVer[@]}; i++ )); do
        nv=$nv${neededVer[$i]}
    done
    iv=$(echo $iv | sed 's/[^0-9]*//g')
    nv=$(echo $nv | sed 's/[^0-9]*//g')
    log "GEN|INFO|Getting count for iv: $iv" t t
    ivCount=${#iv}
    log "GEN|INFO|Getting count for mv: $nv" t t
    nvCount=${#nv}
    log "GEN|INFO|nv: $nv" t t
    log "GEN|INFO|iv: $iv" t t
    log "GEN|INFO|ivCount: $ivCount" t t
    log "GEN|INFO|nvCount: $nvCount" t t
    if [ $ivCount -lt $nvCount ]; then
        ivPad=$(( $nvCount - $ivCount ))
        log "GEN|INFO|ivPad: $ivPad" t t
    elif [ $nvCount -lt $ivCount ]; then
        nvPad=$(( $ivCount - $nvCount ))
        log "GEN|INFO|nvPad: $nvPad" t t
    else
        log "GEN|INFO|No padding needed" t t
    fi
    for (( i=0; i<$nvPad; i++ )); do
        nv=$nv"0"
    done
    for (( i=0; i<$ivPad; i++ )); do
        iv=$iv"0"
    done

    log "GEN|INFO|iv: $iv nv: $nv" t t
    unset ivCount nvCount nvPad ivPad i
    case "$cp" in
        ">")
            if [[ $iv > $nv ]]; then
                return 0
            fi
            ;;
        "<")
            if [[ $iv < $nv ]]; then
                return 0
            fi
            ;;
        "="|"==")
            if [[ $iv == $nv ]]; then
                return 0
            fi
            ;;
        ">=")
            if (( $iv >= $nv )); then
                return 0
            fi
            ;;
        "<=")
            if (( $iv <= $nv )); then
                return 0
            fi
            ;;
        *)
            log "{GEN,ERR}|ERROR|Unknown comparator in checkVersion." t
            return 1
            ;;
    esac

    return 1
}

###
# Dump environment variable
###
function dumpEnv {
    printf "\e[1mEnvironment Var:\e[0m
\e[34mDEBUG: \e[32m$DEBUG
\e[34msd: \e[32m$sd
\e[34msdn: \e[32m$sdn
\e[34mtf: \e[32m$tf
\e[34msdnConf: \e[32m$sdnConf
\e[34mext: \e[32m$ext
\e[34mhasBuildDir: \e[32m$hasBuildDir
\e[34mMAKEFLAGS: \e[32m$MAKEFLAGS
\e[34mbuildDir: \e[32m$buildDir
\e[34mLFS: \e[32m$LFS
\e[34mconfigFile: \e[32m$configFile
\e[34mconfBase: \e[32m$confBase
\e[34mgenLog: \e[32m$genLogFile
\e[34mgenLogFD: \e[32m$genLogFD
\e[34mpkgLog: \e[32m$pkgLogFile
\e[34mpkgLogFD: \e[32m$pkgLogFD
\e[34mimpLog: \e[32m$impLogFile
\e[34mimpLogFD: \e[32m$impLogFD
\e[34merrLog: \e[32m$errLogFile
\e[34merrLogFD: \e[32m$errLogFD\e[0m\n"
}

#!/bin/bash
###
# Params "FDs|LEVEL|MESSAGE" PRINTtoSTDOUT DEBUGONLY
# FDs define 1 or more file descriptor to send the message to. Possible option: GEN,PKG,IMP,ERR
#
# GEN for general log, this log is active when debug is off. Contains general message about progress and results
# PKG Used to log details when debug is on. contains logs from fetching packages  up to installation.
# IMP Used when debug is on to store details about the implementation process from preimplement to postimplement
#     This does not store the information about where files are installed. Those are separate and always active.
# ERR Used when debug is on to store details about the error
# NOTE: More the 1 FD per call can be provided: log "{GEN,ERR}|...."
# PRINTtoSTDOUT when set, also print the message to stdout
#
# DEBUGONLY When set instruct to process log only when debug is on.
###
function log {
    if [ $3 ] && [[ $DEBUG == 0 ]]; then
        return
    fi
    declare LEVEL COLOR MSG M CALLER
    declare -a FDs # Array of file descriptor where messages needs to be redirected to.
    MSGEND="\e[0m" ## Clear all formatting
    IFS='|' read -ra PARTS <<< $1
    case "${PARTS[0]}" in
        \{*)
            IFS=',' read -ra DEST <<< ${PARTS[0]}
            i=0
            while [[ $i < ${#DEST[@]} ]]; do
                t="${DEST[$i]}"
                t="${t/\}}"
                t="${t/\{}"
                case "$t" in
                    GEN) FDs+=($genLogFD);;
                    PKG) FDs+=($pkgLogFD);;
                    IMP) FDs+=($impLogFD);;
                    ERR) FDs+=($errLogFD);;
                esac
                ((i++))
            done
            IFS='|'
            ;;
        GEN) FDs+=($genLogFD);;
        PKG) FDs+=($pkgLogFD);;
        IMP) FDs+=($impLogFD);;
        ERR) FDs+=($errLogFD);;
        NULL|*) FDs+=();;
    esac

    ### Set color formatting
    case "${PARTS[1]}" in
        INFO)
            LEVEL=INFO
            COLOR="\e[35m"
            ;;
        WARNING)
            LEVEL=WARNING
            COLOR="\e[33m"
            ;;
        ERROR)
            LEVEL=ERROR
            COLOR="\e[31m"
            ;;
        FATAL)
            LEVEL=FATAL
            COLOR="\e[31m"
            ;;
    esac

    ### Append message provided by caller
    M="${PARTS[2]}"
    if [[ "$M" = "" ]]; then
        log "NULL|ERROR|Empty log message?!?!" t
    fi

    if [ $sdn ]; then
        caller="\e[32m"$pkg"\e[0m "
        callerLog=$pkg
    else
        callerLog="NONE"
        caller="\e[32mNONE\e[0m "
    fi
    MSG=$COLOR$LEVEL" - "$caller":"$COLOR$M$MSGEND ## Full message string
    LOGMSG=$LEVEL" - "$callerLog":"$M
    if [[ $DEBUG > 0 ]] && [ $3 ]; then
        MSG="\e[33mDEBUG\e[0m - "$MSG
    fi

    ### If $2 is set we also print to stdout.
    if [[ $2 ]]; then
        if [[ ! $FDs ]]; then
            echo -e "NO_DESTINATION -- "$MSG
            return
        fi
        i=0
        displayOnce=0
        while [[ $i < ${#FDs[@]} ]]; do
            if [[ $displayOnce = 0 ]]; then
                echo -e "${FDs[$i]} -- "$MSG
                displayOnce=1 ## Prevents repeat message to stdout when multiple destination are provided.
            fi
            echo $LOGMSG >&${FDs[$i]}
            ((i++))
        done
        unset IFS FDs LEVEL COLOR MSG M MSGEND i
        return
    fi

    ### $2 not set, we do not print to stdout
    if [[ ! $FDs ]]; then
        echo -e "NO_DESTINATION -- "$MSG
    fi
    i=0
    while [[ $i < ${#FDs[@]} ]]; do
        echo -e "${FDs[$i]} -- "$MSG
        echo $LOGMSG >&${FDs[$i]}
        ((i++))
    done
    unset IFS FDs LEVEL COLOR MSG M MSGEND i CALLER
}

function fetchPkg {
    while read -r line; do
        echo $line
        IFS=':' read -ra PARAM <<< "$line"
        case "${PARAM[0]}" in
        esac
        unset IFS
    done < $configFile

    if [[ "$wgetUrl" = "" ]]; then
        log "{GEN,ERR}|ERROR|No url provided. Adjust config file." t
        return
    fi
    wget $wgetUrl $sd/
}

function loadPkg {
    if [[ ! "$pkg" == "" ]]; then
        log "GEN|INFO|Unloading previous package from memory." true
        unloadPkg
    fi
    promptUser "Which package?"
    read pkg
    if [[ "$pkg" == "" ]]; then
        log "ERR|INFO|Empty package provided..."
        return
    fi
    if [ ! -d $confBase/$pkg ]; then
        declare -a foundFiles
        for file in `find $confBase -maxdepth 1 -type d -iname "$pkg*"`; do
            promptUser "FoundFiles: $file\n Use it? Y/n"
            read u
            case $u in
                [nN])
                    continue
                    ;;
                [yY]|*)
                    log "GEN|INFO|Using: $file" t
                    pkg=$(basename $file)
                    if [ ! -d $confBase/$pkg ]; then
                        log "ERR|FATAL|Could not find $pkg after finding it????" true
                        return
                    fi
                    break
                    ;;
            esac
        done
        if [ ! -d $confBase/$pkg ]; then
            log "ERR|FATAL|No package found for $pkg." true
            return
        fi
    fi
    sdnConf=$confBase/$pkg
    log "PKG|INFO|sdnConf set: $sdnConf." t t
    genConfigFile="$sdnConf/$pkg.conf"
    log "PKG|INFO|genConfigFile set: $genConfigFile." t t
    if [ ! -f $genConfigFile ]; then
        log "ERR|ERROR|Package general config file missing" t
        return
    fi

    log "GEN|INFO|Reading config file into variables" t
    while read -r line; do
        IFS=':' read -ra PARAM <<< "$line"
        case "${PARAM[0]}" in
            tf)
                log "PKG|INFO|tf: ${PARAM[1]}" t t
                tf=${PARAM[1]}
                ;;
            sdn)
                log "PKG|INFO|sdn: ${PARAM[1]}" t t
                sdn=${PARAM[1]}
                ;;
            sd)
                log "PKG|INFO|sd: ${PARAM[1]}" t t
                sd=${PARAM[1]}
                ;;
            hasBuildDir)
                log "PKG|INFO|hasBuildDir: ${PARAM[1]}" t t
                hasBuildDir=${PARAM[1]}
                ;;
            bypassImplement)
                log "PKG|INFO|bypassImplement: ${PARAM[1]}" t t
                bypassImplement=${PARAM[1]}
                ;;
            tasks)
                log "PKG|INFO|Loading tasks list." t t
                IFS=',' read -ra TASK <<< "${PARAM[1]}"
                x=0
                while [[ $x < ${#TASK[@]} ]]; do
                    log "PKG|INFO|Adding ${TASK[$x]}." t t
                    autoInstallCmdList+=(${TASK[$x]})
                    ((x++))
                done
                IFS=':'
                ;;
            DEBUG) DEBUG=${PARAM[1]};;
            *) log "{GEN,ERR}|ERROR|Unknow params: ${PARAMS[1]}" t;;
        esac
        unset IFS
    done < $genConfigFile


    log "GEN|INFO|Check if source package exists: $sd/$tf" t
    # Check if source package exists
    if [ ! -f $sd/$tf ]; then
        log "{GEN,ERR}|WARNING|Package $tf not found in source $sd, creating." t t
        processCmd "sudo -u pkm install -vm664 $devBase/sources/$tf $sd/$tf"
        return
    fi

    ext="${tf##*.}"
    log "PKG|INFO|Extension established: $ext" t t
    log "PKG|INFO|Calling setCmdFileList." t t
    setCmdFileList
    if [ $hasBuildDir -lt 1 ]; then
        buildDir=$sd/$sdn/build
        log "GEN|INFO|Checking if build dir: $buildDir exists." t t
        if [ ! -d "$builDir" ]; then
            log "GEN|WARNING|Build directory flag set, but dir does not exist, creating..." t t
            install -vdm755 $buildDir
        fi
    else
        buildDir=$sd/$sdn
    fi
    log "PKG|INFO|buildDir set: $buildDir." t t
    ### Not needed with the new pipe logs.
    #    logDir="/var/log/pkm/$sdn"
    #    log "GEN|INFO|Checking log directorie: $ld" t
    #    if [ ! -d "$logDir" ]; then
    #        log "{GEN,ERR}|WARNING|Package log directory not found, creating." true
    #        mkdir $logDir
    #    fi

    # Adjusting the unpack commands
    log "GEN|INFO|Adjusting unpack command." t
    if [[ "$ext" == "xz" ]]; then
        unpackCmd="tar xvf $tf"
    elif [[ "$ext" == "gz" ]]; then
        unpackCmd="tar xvfz $tf"
    elif [[ "$ext" == "gzip" ]]; then
        unpackCmd="tar xvfz $tf"
    elif [[ "$ext" == "bz2" ]]; then
        unpackCmd="tar xvfj $tf"
    elif [[ "$ext" == "tgz" ]]; then
        unpackCmd="tar xvfz $tf"
    else
        log "ERR|FATAL|Unknown package unpack method." true
        return
    fi
    log "PKG|INFO|unpackCmd set: $unpackCmd." t t
}

###
# Unload package from memory, reset environment variable to their default and call readConfig to reload configuration.
###
function unloadPkg {
    unset -v pkg sdnConf tf sdn hasBuildDir buildDir ld ext unpackCmd banner genConfigFile depcheckCmdFile preconfigCmdFile configCmdFile compileCmdFile checkCmdFile preInstallCmdFile installCmdFile preImplementCmdFile postImplementCmdFile cmdFileList preconfigCmd configCmd compileCmd checkCmd preInstallCmd installCmd preImplementCmd postImplementCmd autoInstallCmdList
    isImplemented=1
}

###
# Call to unpack source code.
# The unpackCmd is set when loadPkg is called.
###
function unpack {
    log "{GEN,PKG}|INFO|Unpacking source code $tf" true

    if [ ! -f $sd/$tf ]; then
        log "{GEN,PKG,ERR}|FATAL|$tf not found." true
        return 1
    fi

    log "PKG|INFO|Running Cmd: $unpackCmd" true
    pushd $sd > /dev/null
    if [[ $? > 0 ]]; then
        log "{GEN,PKG,ERR}|FATAL|pushd to $sd failed." true
        return 2
    fi
    processCmd "${unpackCmd}"
    if [ $hasBuildDir == 0 ]; then
        log "PKG|INFO|Creating build directory" true
        processCmd "install -opkm -gpkm -vdm755 $sd/$sdn/build"
    fi

    log "{GEN,PKG}|INFO|Done." t
    popd > /dev/null 2>&1
}

###
# Auto install takes its task list from the package config file.
# This function will simply display the list of task and request confirmation from the user.
###
function autoInstall {
    log "GEN|INFO|AutoInstall: Will be running the following tasks:"
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

###
# Run the autoinstall
###
function runAutoInstall {
    i=0
    while [[ $i < ${#autoInstallCmdList[@]} ]]; do
        f=${autoInstallCmdList[$i]}
        fbase=$(basename $f)
        echo "$fbase"
        if [ "$fbase" = "postImplement" ]; then
            if [[ $bypassImplement > 0 ]]; then
                log "GEN|INFO|Post Implement detected, running Implement first." true
                implementPkg
                isImplemented=0
            else
                log "GEN|INFO|Post Implement detected, and bypass Implement flag is set." true
            fi
        fi
        log "GEN|INFO|Sourcing $f." true
        evalPrompt $fbase
        res=$?
        if [[ $res > 0 ]]; then
            log "{PKG,ERR}|ERROR|Error sourcing $f." true
            return $res
        fi
        if [ "$fbase" = "check" ]; then
            promptUser "Just finished checks, verify it. Do I keep going? Y/n"
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
        log "{GEN,PKG}|INFO|Implementing pkg." t
        implementPkg
        isImplemented=0
    fi
    cleanup
    return 0
}

function downloadPkg {
    declare -a urls
    done=0
    log "GEN|INFO|Downloading packages, enter 1 url per line, finish with empty line." t
    while [ $done -lt 1 ];do
        read u
        if [ "$u" = "" ];then
            done=1
            continue
        fi
        urls+=(${u})
    done
    x=0
    pushd /tmp >/dev/null
    if [[ $? > 0 ]]; then
        log "{GEN,ERR}|FATAL|Unable to pushd $sd" t
        return
    fi
    log "GEN|INFO|Downloading...." t
    while [ $x -lt ${#urls[@]} ]; do
        pkg=$(basename ${urls[$x]})
        processCmd "sudo -u pkm wget ${urls[$x]} -vO $sd/$pkg"
        ((x++))
    done
    popd
    unset x urls done
}

function searchPkg {
    # If we can't file the package (source tar), we do a search for the term provided by the user.
    declare -a foundFiles
    for file in `find $sd -maxdepth 1 -type f -iname "$1*"`; do
        promptUser "FoundFiles: $file\n Use it? Y/n"
        read u
        case $u in
            [nN])
                continue
                ;;
            [yY]|*)
                log "GEN|INFO|Using: $file" true
                pkg=$(basename $file)
                log "{GEN,PKG}|INFO|pkg set to $pkg" t t
                if [ ! -f $sd/$pkg ]; then
                    log "{GEN,ERR}|FATAL|Could not find $pkg after finding it????" true
                    return
                fi
                break
                ;;
        esac
    done
    if [ ! -f $sd/$pkg ]; then
        log "GEN|WARNING|No package found for $pkg*." true
        promptUser "Do you want to download? Y/n"
        read u
        case $u in
            [nN])
                pkg="NA"
                return
                ;;
            [yY]|*)
                downloadPkg
                pkg="NA"
                return
                ;;
        esac
    fi
}

function createSkeleton {
    if [ -d $sdnConf ]; then
        log "GEN|WARNING|Config Directory exists. Previous configuration file will be left intact." t
        return
    fi
    log "GEN|INFO|Installing $sdnConf" t t
    processCmd "sudo -u pkm install -vdm775 -o pkm -g pkm $sdnConf"

    echo -n "Does the package requires a build directory? y/N "
    read d
    case $d in
        [yY])
            log "GEN|INFO|Adjusting script config for build directory" t
            buildDir="$sd/$sdn/build"
            hasBuildDir=0
            ;;
        *)
            buildDir="$sd/$sdn"
            hasBuildDir=1
            ;;
    esac
    log "GEN|INFO|buildDir set to: $buildDir." t t
    log "GEN|INFO|Creating general config file with default values." t
    tconf="tf:$tf\nsdn:$sdn\nhasBuildDir:$hasBuildDir\nbypassImplement:1\ntasks:unpack,implement,cleanup"
    genConfigFile="$sdnConf/$sdn.conf"
    processCmd "sudo -u pkm touch $genConfigFile"
    processCmd "sudo -u pkm chmod 666 -v $genConfigFile"
    echo -e $tconf > "${genConfigFile}"

    cmdArrLen=${#cmdFileList[@]}
    log "GEN|INFO|Installing configuration files." t
    processCmd "sudo -u pkm install -g pkm -o pkm -m664 -v $confBase/templates/* $sdnConf/"
    log "GEN|INFO|Done." t

}

function prepPkg {
    unloadPkg
    promptUser "Package name?"
    read -e inputPkg
    if [ "$inputPkg" = "" ]; then
        log "GEN|INFO|Empty package provided." t
        return
    fi
    log "GEN|INFO|Searching for $pkg." t
    searchPkg $inputPkg
    if [ "$pkg" = "NA" ]; then
        log "GEN|WARNING|Not found in search. If you just downloaded file, this message is normal." t
        return
    fi
    log "GEN|INFO|Pkg: $pkg found." t
    tf=$pkg
    log "GEN|INFO|tf: $tf" t t
    ext="${tf##*.}"
    log "GEN|INFO|ext:$ext" t t
    local unpackOpt
    if [[ "$ext" == "xz" ]]; then
        unpackOpt="-tf"
    elif [[ "$ext" == "gz" ]]; then
        unpackOpt="-tfz"
    elif [[ "$ext" == "gzip" ]]; then
        unpackOpt="-tfz"
    elif [[ "$ext" == "bz2" ]]; then
        unpackOpt="-tfj"
    elif [[ "$ext" == "tgz" ]]; then
        unpackOpt="-tfz"
    fi
    log "GEN|INFO|Establishing sdn..." t t
    sdn=`tar $unpackOpt $sd/$pkg |head -n1 |sed -e 's/\/.*//' | sed -e 's/^\.//' |sed ':a;N;$!ba;s/\n//' |uniq`
    
    if [[ "$sdn" = "" ]]; then
        sdn=`tar $unpackOpt $sd/$pkg |head -n2 |sed -e 's/\/.*//' | sed -e 's/^\.//' |sed ':a;N;$!ba;s/\n//' |uniq`
        if [[ "$sdn" = "" ]]; then
                    log "GEN|WARNING|Unable to set sdn." t
                    promptUser "Enter sdn: "
                    read sdn
        fi
    fi
    log "GEN|INFO|snd set to: $sdn" t t
    sdnConf="$confBase/$sdn"
    log "GEN|INFO|sdnConf set to: $sdnConf" t t
    log "GEN|INFO|Calling setCmdFileList" t t
    setCmdFileList
    if [[ $? > 0 ]]; then
        log "{GEN,ERR}|ERROR|setCmdFileList returned 1 unable to continue." t t
        return 1
    fi
    log "GEN|INFO|setCmdFileList done." t t
    log "GEN|INFO|Calling createSkeleton." t t
    createSkeleton
    log "GEN|INFO|CreateSkeleton done." t t
}

function processCmd {
    local cmd=""
    for part in $@; do
        cmd=$cmd" "$part
    done
    if [[ $DEBUG = 0 ]]; then
        $cmd 2>&1 >/dev/null
    elif [[ $DEBUG = 1 ]]; then
        $cmd >&${pkgLogFD} 2>&${errLogFD}
    else
        $cmd > >(tee >(cat - >&${pkgLogFD})) 2> >(tee >(cat - >&${errLogFD}) >&2)
    fi
    return $?
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

###
# Provide this command with a string parameter representing the prompt to the user.
# This function is here to ensure standard user prompt throught the application
###
function promptUser {
    COLOR="\e[37m"
    echo -en $COLOR$1" : \e[0m"
}

###
# Sourcing our commmands scripts here
###
function sourceScript {
    c=$1
    log "GEN|INFO|Sourcing: $c" t t
    source $c
    res=$?
    log "GEN|INFO|Sourced $c returned: $res" t t
    return $res
}

###
# Cleanup after package source and fakeroot directories
###
function cleanup {
    log "GEN|INFO|Cleaning up source file" t
    pushd $sd > /dev/null
    if [[ $? > 0 ]]; then
        log "{GEN,ERR}|FATAL|pushd to $sd failed." t
        exit 1
    fi

    rm -fr $sdn
    popd > /dev/null 2>&1
}

###
# Populate cmd files variable
###
function setCmdFileList {
    log "GEN|INFO|Setting up command files list." true
    if [[ "$sdn" = "" ]]; then
        log "{GEN,ERR}|ERROR|sdn is not set." true
        return 1
    fi
    if [ "$sdnConf" == "" ]; then
        log "{GEN,ERR}|ERROR|sdnConf not set." true
        return 1
    fi

    depcheckCmdFile=$sdnConf/depcheck
    preconfigCmdFile=$sdnConf/preconfig
    configCmdFile=$sdnConf/config
    compileCmdFile=$sdnConf/compile
    checkCmdFile=$sdnConf/check
    preInstallCmdFile=$sdnConf/preinstall
    installCmdFile=$sdnConf/install
    preImplementCmdFile=$sdnConf/preimplement
    postImplementCmdFile=$sdnConf/postimplement
    cmdFileList=(
        $depcheckCmdFile
        $preconfigCmdFile
        $configCmdFile
        $compileCmdFile
        $checkCmdFile
        $preInstallCmdFile
        $installCmdFile
        $preImplementCmdFile
        $postImplementCmdFile
    )
    return 0
}

function listTask {
    i=0
    while [[ $i < ${#autoInstallCmdList[@]} ]]; do
        echo -n "${autoInstallCmdList[$i]}, "
        ((i++))
    done
    echo ""
}

function evalPrompt {
    case $1 in
        listcommands)
            listCommands
            ;;
        fetch)
            fetchPkb
            ;;
        unpack)
            unpack
            ;;
        depcheck)
            log "GEN|INFO|Running dependency check scripts" true
            sourceScript "${depcheckCmdFile}"
            ;;
        preconfig)
            if [ $hasBuildDir -lt 1 ]; then
                pushd $sd/$sdn > /dev/null
            else
                pushd $buildDir >/dev/null
            fi
            if [[ $? > 0 ]]; then
                log "ERR|FATAL|pushd to $buildDir failed." true
                return 1
            fi
            sourceScript "${preconfigCmdFile}"
            log "GEN|INFO|Running pre-config scripts" true
            popd > /dev/null 2>&1
            ;;
        config)
            log "GEN|INFO|Running config scripts" true
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "ERR|FATAL|pushd to $buildDir failed." true
                return 1
            fi
            sourceScript "${configCmdFile}"
            popd > /dev/null 2>&1
            ;;
        compile)
            log "GEN|INFO|Running compile scripts" true
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "ERR|FATAL|pushd to $buildDir failed." true
                exit 1
            fi
            sourceScript "${compileCmdFile}"
            popd > /dev/null 2>&1
            ;;
        check)
            log "GEN|INFO|Running check scripts" true
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "ERR|FATAL|pushd to $buildDir failed." true
                return 1
            fi
            sourceScript "${checkCmdFile}"
            popd > /dev/null 2>&1
            ;;
        preinstall)
            log "GEN|INFO|Running PreInstall scripts" true
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "ERR|FATAL|pushd to $buildDir failed." true
                return 1
            fi
            sourceScript "${preInstallCmdFile}"
            popd > /dev/null 2>&1
            ;;
        install)
            log "GENINFO|Running install scripts" true
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "ERR|FATAL|pushd to $buildDir failed." true
                return 1
            fi
            sourceScript "${installCmdFile}"
            popd > /dev/null 2>&1
            ;;
        preimplement)
            log "GEN|INFO|Running preImplement scripts" true
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "ERR|FATAL|pushd to $buildDir failed." true
                return 1
            fi
            sourceScript "${preImplementCmdFile}"
            popd > /dev/null 2>&1
            ;;
        implement)
            if [[ $bypassImplement < 1 ]]; then
                log "{GEN,ERR}|ERROR|bypassImplement flag is set, unable to proceed with implement request." t
                return 1
            fi
            log "GEN|INFO|Running implement procedure." t
            implementPkg
            ;;
        postimplement)
            log "GEN|INFO|Running PostImplement scripts" true
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "ERR|FATAL|pushd to $buildDir failed." true
                return 1
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
        debug)
            if [[ "$2" = "" ]]; then
                return
            fi
            DEBUG=$2
            ;;
        reload)
            readConfig
            ;;
        quit)
            log "GEN|INFO|Quitting"
            exec {genLogFD}>&-
            exec {pkgLogFD}>&-
            exec {impLogFD}>&-
            exec {errLogFD}>&-
            unset genLogFile pkgLogFile impLogFile errLogFile
            unset genLogFD pkgLogFD impLogFD errLogFD

            if [ -f $devBase/var/run/pkm/pkm.lock ]; then
                log "GEN|INFO|Removing pkm lock." t
                sudo -u pkm rm -v $devBase/var/run/pkm/pkm.lock
            fi
            CURSTATE=1
            ;;
        ilsil)
            importLfsScriptedImplementLogs
            ;;
        *)
            log "GEN|INFO|Unknown command: $1" t
            ;;
    esac

}

function prompt {
    while [[ $CURSTATE == [0] ]]; do
        promptUser "Input."
        read -e command
        evalPrompt $command
    done
}


singleton ## Ensure only one instance runs.
if [[ $? > 0 ]]; then
    exit 1
fi
log "NULL|INFO|Starting PKM" t
readConfig
startupCheck
log "NULL|INFO|Configuration loaded." t
log "NULL|INFO|Starting log managers" t
startLog
prompt
