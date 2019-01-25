#!/bin/bash

declare devBase="/home/lfs/lfsScripted"
declare configFile="$devBase/etc/pkm.conf"
declare sd td sdn sdnConf pkg ext hasBuildDir buildDir confBase wgetUrl LFS lfsUserHome
declare -a partitionDev partitionName partitionMount partitionFs
declare unpackCmd
declare MAKEFLAGS
declare DEBUG=0 # 0=OFF, 1= ON, debug is always sent to log file, turn on make is print to stdOut
declare genLogFile pkgLogFile errLogFile
declare genLogFD pkgLogFD errLogFD #File descriptor input only
declare bypassImplement=0 # Implementation bypassed in temp toolchain, we do not use fakeroot.

# Config files
declare genConfigFile depcheckCmdFile preconfigCmdFile configCmdFile compileCmdFile checkCmdFile
declare preInstallCmdFile installCmdFile
declare -a cmdFileList
declare -a autoInstallCmdList

function singleton {
    if [ -f $devBase/var/run/pkm/pkm.lock ]; then
        echo "Pkm is already running or has not quit properly, in that case, remove $devBase/var/run/pkm/pkm.lock" t
        return 1
    fi
    touch $devBase/var/run/pkm/pkm.lock
    [ $? -gt 0 ] && echo "Unable to create lock file. Ensure only 1 instance is running."

    # If we are lfs user, we assume installation is done and proceed as normal.
    usr=`whoami`
    if [[ $usr == "lfs" ]]; then
        echo "We are lfs, we assume this is a normal startup."
        return 0
    fi

    ## We are not lfs user, but if it exists, warn to run as lfs
    grep -q lfs < /etc/passwd
    if [[ $? == 0 ]] && [ $USER != "lfs" ]; then
        quitPkm 1 "Run this program as lfs user."
    fi

    ## We are not lfs user and it does not exists, install lfsScripted.
    readConfig
    startlog
    startupCheck
    log "GEN|INFO|Installing lfsScripted into lfs home folder." t
    processCmd "sudo cp -fr $devBase $lfsUserHome"
    [ $? -gt 0 ] && quitPkm 1 "Error copy $devBase -> $lfsUserHome"
    checkPerm $lfsUserHome/$devBase
    [ $? -gt 0 ] && quitPkm 1 "Error in checkPerm $lfsUserHome/$devBase"
    echo "Su to lfs user, check pkm.conf and variable in pkm.sh"
    echo "Then you can run the installer."
    quitPkm 0
}

## Copy all source script folders in etc into lfs installation.
## This command is only usefull when in development.
function updatePkgFromLocal {
    readConfig
    startLog
    log "GEN|INFO|Making backup of pkm.conf in $lfsUserHome" t
    processCmd "sudo cp -fv $lfsUserHome/lfsScripted/etc/pkm.conf $lfsUserHome/lfsScripted/etc/pkm.conf.bak"

    log "GEN|INFO|Copy source scripts to $lfsUserHome" t
    processCmd "sudo cp -frv .//etc/* $lfsUserHome/lfsScripted/etc/"

    log "GEN|INFO|Restaure pkm.conf it got overwriten." t
    processCmd "sudo mv -v $lfsUserHome/lfsScripted/etc/pkm.conf.bak $lfsUserHome/lfsScripted/etc/pkm.conf"

    checkPerm $lfsUserHome/lfsScripted
    checkPerm $lfsUserHome/lfsScripted/etc
    [ $? -gt 0 ] && quitPkm 1 "Error with checkPerm in updatePkgFromLocal"
    return 0
}

## Similar to uploadPkgFromLocal this function is called from the CLI arg passed to pkm.sh
## Used in development to update lfs version of pkm.sh
function updatePkm {
    readConfig
    startLog
    log "GEN|INFO|Installing pkm.sh into lfs home." t
    processCmd "sudo cp -vf ./pkm.sh $lfsUserHome/lfsScripted"
    [ $? -gt 0 ] && quitPkm 1 "Error with cp pkm.sh to lfs"
    checkPerm $lfsUserHome/lfsScripted/pkm.sh
    [ $? -gt 0 ] && quitPkm 1 "Error with checkPerm in updatePkm."
    echo "Remember check top 2 variable."
    quitPkm 0
}

function startLog {
    if [ ! -f $genLogFile ]; then
        log "NULL|INFO|Creating $genLogFile" t
        touch $genLogFile
        chmod 666 -v $genLogFile
    fi
    if [ ! -f $pkgLogFile ]; then
        log "NULL|INFO|Creating $pkgLogFile" t
        touch $pkgLogFile
        chmod 666 -v $pkgLogFile
    fi
    if [ ! -f $errLogFile ]; then
        log "NULL|INFO|Creating $errLogFile" t
        touch $errLogFile
        chmod 666 -v $errLogFile
    fi
    log "NULL|INFO|Creating file descriptor for logs" t
    exec {genLogFD}>$genLogFile
    exec {pkgLogFD}>$pkgLogFile
    exec {errLogFD}>$errLogFile

}

###
# Read config file stored in $configFile
###
function readConfig {
    log "NULL|INFO|Reading configuration file." t
    if [ ! -f $configFile ]; then
        log "NULL|ERROR|Configuration file: $configfile is missing." t
        quitPkm 1
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
                log "NULL|INFO|Set param sd:$sd" t
                ;;
            confBase)
                confBase=${PARAM[1]}
                log "NULL|INFO|Set param confBase:$confBase" t
                ;;
            MAKEFLAGS)
                MAKEFLAGS=${PARAM[1]}
                log "NULL|INFO|Set param MAKEFLAGS:$MAKEFLAGS" t
                ;;
            bypassImplement)
                bypassImplement=${PARAM[1]}
                log "NULL|INFO|Set param bypassImplement:$bypassImplement" t
                ;;
            genLog)
                genLogFile=${PARAM[1]}
                log "NULL|INFO|Set param genLogFile:$genLogFile" t
                ;;
            pkgLog)
                pkgLogFile=${PARAM[1]}
                log "NULL|INFO|Set param pkgLogFile:$pkgLogFile" t
                ;;
            errLog)
                errLogFile=${PARAM[1]}
                log "NULL|INFO|Set param errLogFile:$errLogFile" t
                ;;
            partitionDev)
                partitionDev=(${PARAM[1]})
                log "NULL|INFO|Set param partitionDev:$partitionDev" t
                ;;
            partitionName)
                partitionName=(${PARAM[1]})
                log "NULL|INFO|Set param partitionName:$partitionName" t
                ;;
            partitionMount)
                partitionMount=(${PARAM[1]})
                log "NULL|INFO|Set param partitionMount:$partitionMount" t
                ;;
            partitionFs)
                partitionFs=(${PARAM[1]})
                log "NULL|INFO|Set param partitionFs:$partitionFs" t
                ;;
            LFS)
                LFS=${PARAM[1]}
                log "NULL|INFO|Set param LFS:$LFS" t
                ;;
            lfsUserHome)
                lfsUserHome=${PARAM[1]}
                log "NULL|INFO|Set param lfsUserHome:$lfsUserHome" t
                ;;
            "#") continue;;
            *) continue;;
        esac
        unset IFS
    done < $configFile
    export MAKEFLAGS
    log "NULL|INFO|Done reading config file." t
}

function mountLfs {
    log "GEN|INFO|Checking mountpoint." t
    if [ ! -d $LFS ]; then
        log "GEN|ERROR|Mount point $LFS does not exist. Creating." t
        processCmd "sudo mkdir -pv $LFS"
    fi
    log "GEN|INFO|Mounting partitions." t
    x=0
    pl=${#partitionName[@]}
    log "GEN|INFO|Got $pl partition to mount." t
    while [ $x -lt $pl ]; do
        pn=${partitionName[$x]}
        pm=${partitionMount[$x]}
        pd=${partitionDev[$x]}
        pf=${partitionFs[$x]}

        if [[ "$pn" = "swap" ]]; then
            if [[ `grep /dev/ < <(sudo swapon -s) |wc -l` < 1 ]]; then
                log "GEN|INFO|Found swap partition, Ativating." t
                processCmd "sudo /sbin/swapon -v $pd"
                log "GEN|WARNING|Swap should be last to mount, if not, next partition will not be mounted." t
                return 0
            else
                log "GEN|INFO|Swap already active, skipping." t
                return 0
            fi
        fi

        if [ ! -d $LFS$pm ]; then
            log "GEN|WARNING|$LFS$pm does not exists, creating." t
            processCmd "sudo mkdir -pv $LFS$pm"
        fi
        log "GEN|INFO|Check if $pd mounted on $pm" t
        if [[ `grep "$pd on $pm" < <(mount) | wc -l` < 1 ]]; then
            log "GEN|INFO|Mounting $pd on $pm" t
            processCmd "sudo mount -v -t $pf $pd $LFS$pm"
            ((x++))
        else
            log "GEN|INFO|$pd already mounted on $pm, skipping." t
            ((x++))
        fi
    done
    return 0
}

function unMountLfs {
    log "GEN|INFO|UnMounting partitions." t
    x=0
    pl=${#partitionName[@]}
    log "GEN|INFO|Got $pl partition to unmount." t
    while [ $x -lt $pl ]; do
        pn=${partitionName[$x]}
        pm=${partitionMount[$x]}
        pd=${partitionDev[$x]}
        pf=${partitionFs[$x]}

        if [[ "$pn" = "swap" ]]; then
            log "GEN|WARN|Not turning off swap, there is a host system active." t
            break
        fi

        log "GEN|INFO|Check if $pd mounted on $pm" t
        if [[ `grep "$pd on $pm" < <(mount) | wc -l` > 0 ]]; then
            log "GEN|INFO|Unmounting $pd from $pm" t
            processCmd "sudo umount -v $pd"
            [ $? -gt 0 ] && log "{GEN,ERR}|ERROR|Error unmounting $pd, check manually." t
        else
            log "GEN|INFO|$pd not mounted." t
        fi
        ((x++))
    done
    return 0
}

function checkSources {
    log "GEN|INFO|Checking if source directory $sd exists." t
    if [ ! -d $sd ]; then
        log "GEN|WARNING|Source directory $sd does not exists, creating." t
        processCmd "sudo mkdir -vp $sd"
        processCmd "sudo chmod -v a+wt $sd"
    fi
    log "GEN|INFO|Done." t

    log "GEN|INFO|Do we have wget.list?" t
    if [ ! -f $confBase/wget.list ]; then
        log "GEN|WARNING|wget.list not found, fetching." t
        processCmd "sudo wget -v -O $confBase/wget.list -v \"http://www.linuxfromscratch.org/lfs/view/stable/wget-list\""
    fi
    log "GEN|INFO|Do we have md5sums?" t
    if [ ! -f $confBase/md5sums ]; then
        log "GEN|WARNING|md5sums not found, fetching." t
        processCmd "sudo wget -v -O $confBase/md5sums -v \"http://www.linuxfromscratch.org/lfs/view/stable/md5sums\""
    fi

    log "GEN|INFO|Checking source packages." t
    for line in `cat $confBase/wget.list`; do
        fn=$(basename $line)
        log "GEN|INFO|Checking for $fn"
        if [ ! -f $sd/$fn ]; then
            log "GEN|INFO|$fn not found, fetching." t
            if [[ $DEBUG > 0 ]]; then
                processCmd "sudo wget -v $line -O $sd/$fn"
            else
                processCmd "sudo wget -v $line -O $sd/$fn >/dev/null"
            fi
        fi
    done
    # Touch dummy pkg
    if [ ! -e $sd/versionCheck.tar.xz ]; then
        log "GEN|INFO|Creating dummy packages" t
        processCmd "sudo touch $sd/versionCheck.tar.xz"
    fi
    log "GEN|INFO|Checking md5." t
    mPush $sd
    processCmd "sudo md5sum -c $confBase/md5sums"
    [ $? -gt 0 ] && mPop && log "{GEN,ERR}|ERROR|Source md5sum check failed. Check logs for details." t && return 1
    mPop
    return 0
}

function checkLfsUser {
    log "GEN|INFO|Checking LFS group & user." t
    grep -q lfs < /etc/group
    if [[ $? > 0 ]]; then
        log "GEN|WARNING|lfs group does not exists, creating." t
        processCmd "sudo groupadd lfs"
        [ $? -gt 0 ] && return 1
    fi

    grep -q lfs < /etc/passwd
    if [[ $? > 0 ]];then
        log "GEN|WARNING|lfs user not found. Fixing." t
        processCmd "sudo useradd -s /bin/bash -g lfs -d $lfsUserHome -m -k $devBase/etc/lfsHomeSkel lfs"
        [ $? -gt 0 ] && return 1

        log "GEN|INFO|Set password for lfs user." t
        processCmd "sudo passwd lfs"
        [ $? -gt 0 ] && return 1
    fi
    return 0

}

function checkStruct {
    log "GEN|INFO|Checking $LFS/tools." t
    if [ ! -d $LFS/tools ]; then
        log "GEN|WARNING|$LFS/tools does not exists, creating." t
        processCmd "sudo mkdir -pv $LFS/tools"
        [ $? -gt 0 ] && return 1
    fi
    if [ ! -h /tools ]; then
        log "GEN|WARNING|/tools does not exists, creating." t
        processCmd "sudo ln -sv $LFS/tools /"
        [ $? -gt 0 ] && return 1
    fi
    return 0
}

function checkPerm {
    log "GEN|INFO|Checking permission and ownership" t
    declare -a toCheck
    if [ $1 ]; then
        toCheck=($1)
    else
        toCheck=($LFS/tools $sd $devBase/etc $devBase/var $lfsUserHome)
    fi
    for d in ${toCheck[@]}; do
        log "GEN|INFO|Check permissions and owners of $d" t
        if [ -d $d ]; then
            for file in $d/*; do
                user=`stat -c %U $file`
                log "GEN|INFO|Owner of $file: $user"
                if [[ ! "$user" = "lfs" ]]; then
                    log "GEN|INFO|Fixing ownership of $file." t
                    processCmd "sudo chown -vR lfs:lfs $file"
                    processCmd "sudo chmod g+w -vR $file"
                fi

            done
        elif [ -f $d ]; then
            user=`stat -c %U $d`
            log "GEN|INFO|Owner of $file: $user"
            if [[ ! "$user" = "lfs" ]]; then
                log "GEN|INFO|Fixing ownership of $file." t
                processCmd "sudo chown -v lfs:lfs $file"
                processCmd "sudo chmod g+w -v $file"
            fi
        fi
    done
}

function startupCheck {
    log "GEN|INFO|Checking environment." t
    checkLfsUser
    [ $? -gt 0 ] && quitPkm 1 "Error with checkLfsUser"
    mountLfs
    [ $? -gt 0 ] && quitPkm 1 "Error with mountLfs"
    checkSources
    [ $? -gt 0 ] && log "GEN|ERROR|Error with checkSources, make sure all is good." t
    checkStruct
    [ $? -gt 0 ] && quitPkm 1 "Error with checkStruct, to risky to continue."
    checkPerm
    [ $? -gt 0 ] && quitPkm 1 "Errpr with checkPerm, to risky to continue."
    return 0
}

function checkInstalled {
    processCmd "command -v "$1
    [ $? -gt 0 ] && return 1 || return 0
}

function checkLibInstalled {
    processCmd "sudo ldconfig -p | grep $1"
    [ $? -gt 0 ] && return 1 || return 0
}

function getVersion {
    reqCmd="$1"
    log "GEN|INFO|Getting version of "$reqCmd t
    cmdVersion=`timeout 5 $1 --version 2>&1  | sed '/^$/d' |head -n1 | egrep -o "([0-9]{1,}\.)+[0-9]{1,}"`
    if [[ $? > 0 ]]; then
        log "PKG|WARNING|Unable to fetch version, attempting another way." t
        cmdVersion=`$1 -version 2>&1  | sed '/^$/d' |head -n1 | egrep -o "([0-9]{1,}\.)+[0-9]{1,}"`
        if [[ $? > 0 ]]; then
            log "PKG|ERROR|Could not find version for $1." t
            return 1
        fi
    fi
    log "PKG|INFO|Found version: $cmdVersion." t
    log "GEN|INFO|Removing all non numeric character." t
    cmdVersion=$(echo $cmdVersion | sed 's/[^0-9]*//g')
    log "GEN|INFO|cmdVersion: $cmdVersion." t
    eval "$2=$cmdVersion"
    [ $? -gt 0 ] && return 1 || return 0
}

function vercomp {
    declare cp='>='; ## Default comparator if not provided
    if [[ $3 ]]; then
        cp=$3
    fi
    log  "GEN|INFO|Comparing version: $1 $cp $2" t
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
    log "GEN|INFO|Getting count for iv: $iv" - t
    ivCount=${#iv}
    log "GEN|INFO|Getting count for mv: $nv" - t
    nvCount=${#nv}
    log "GEN|INFO|nv: $nv" - t
    log "GEN|INFO|iv: $iv" - t
    log "GEN|INFO|ivCount: $ivCount" - t
    log "GEN|INFO|nvCount: $nvCount" - t
    if [ $ivCount -lt $nvCount ]; then
        ivPad=$(( $nvCount - $ivCount ))
        log "GEN|INFO|ivPad: $ivPad" - t
    elif [ $nvCount -lt $ivCount ]; then
        nvPad=$(( $ivCount - $nvCount ))
        log "GEN|INFO|nvPad: $nvPad" - t
    else
        log "GEN|INFO|No padding needed" - t
    fi
    for (( i=0; i<$nvPad; i++ )); do
        nv=$nv"0"
    done
    for (( i=0; i<$ivPad; i++ )); do
        iv=$iv"0"
    done

    log "GEN|INFO|iv: $iv nv: $nv" - t
    unset ivCount nvCount nvPad ivPad i
    case "$cp" in
        ">")
            [ $iv -gt $nv ] && return 0 || return 1
            ;;
        "<")
            [ $iv -lt $nv ] && return 0 || return 1
            ;;
        "="|"==")
            [ $iv -eq $nv ] && return 0 || return 1
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

###
# Params "FDs|LEVEL|MESSAGE" PRINTtoSTDOUT
# FDs define 1 or more file descriptor to send the message to. Possible option: GEN,PKGERR
#
# GEN for general log, this log is active when debug is off. Contains general message about progress and results
# PKG Used to log details when debug is on. contains logs from fetching packages  up to installation.
# ERR Used when debug is on to store details abouthe error
# NOTE: More the 1 FD per call can be provided: log "{GEN,ERR}|...."
# PRINTtoSTDOUT when set, also printhe message to stdout
###
function log {
    if [ $3 ] && [[ $DEBUG = 0 ]]; then
          return
    fi
    declare LEVEL COLOR MSG M CALLER
    declare -a FDs # Array of file descriptor where messages needs to be redirected to.
    MSGEND="\e[0m" ## Clear all formatting

    ## Setting up file descriptor destination
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
                    ERR) FDs+=($errLogFD);;
                esac
                ((i++))
            done
            IFS='|'
            ;;
        GEN) FDs+=($genLogFD);;
        PKG) FDs+=($pkgLogFD);;
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
    ### If $debug is set
    if [[ $DEBUG > 0 ]]; then
        if [[ ! $FDs ]]; then
            ## There is no file descriptor setup, printo stdOut and bail
            echo -e "NO_DESTINATION -- "$MSG
            unset IFS FDs LEVEL COLOR MSG M MSGEND i CALLER
            return
        fi
        i=0
        displayOnce=0
        while [[ $i < ${#FDs[@]} ]]; do
            echo $LOGMSG >&${FDs[$i]}
            ((i++))
        done
    fi

    # Printo stdOut
    if [[ $2 ]] && [[ "$2" = "t" ]]; then
        echo -e $MSG
    fi

    unset IFS FDs LEVEL COLOR MSG M MSGEND i CALLER
    return
}

function loadPkg {
    if [[ $pkg ]]; then
        log "GEN|INFO|Unloading $pkg from memory." t
        unloadPkg
    fi
    promptUser "Which package?"
    read pkg
    if [[ "$pkg" == "" ]]; then
        log "ERR|INFO|Empty package provided..."
        return 1
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
                        log "ERR|FATAL|Could not find $pkg after finding it????" t
                        return 1
                    fi
                    break
                    ;;
            esac
        done
        if [ ! -d $confBase/$pkg ]; then
            log "ERR|FATAL|No package found for $pkg." t
            return 1
        fi
    fi
    sdnConf=$confBase/$pkg
    log "PKG|INFO|sdnConf set: $sdnConf." t
    genConfigFile="$sdnConf/$pkg.conf"
    log "PKG|INFO|genConfigFile set: $genConfigFile." t
    if [ ! -f $genConfigFile ]; then
        log "ERR|ERROR|Package general config file missing" t
        return
    fi

    log "PKG|INFO|Reading config file into variables" t
    while read -r line; do
        IFS=':' read -ra PARAM <<< "$line"
        case "${PARAM[0]}" in
            tf)
                log "PKG|INFO|tf: ${PARAM[1]}" t
                tf=${PARAM[1]}
                ;;
            sdn)
                log "PKG|INFO|sdn: ${PARAM[1]}" t
                sdn=${PARAM[1]}
                ;;
            sd)
                log "PKG|INFO|sd: ${PARAM[1]}" t
                sd=${PARAM[1]}
                ;;
            hasBuildDir)
                log "PKG|INFO|hasBuildDir: ${PARAM[1]}" t
                hasBuildDir=${PARAM[1]}
                ;;
            bypassImplement)
                log "PKG|INFO|bypassImplement: ${PARAM[1]}" t
                bypassImplement=${PARAM[1]}
                ;;
            tasks)
                log "PKG|INFO|Loading tasks list." t
                IFS=',' read -ra TASK <<< "${PARAM[1]}"
                x=0
                while [[ $x < ${#TASK[@]} ]]; do
                    log "PKG|INFO|Adding ${TASK[$x]}." t
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
    ## What is this
    if [ ! -f $sd/$tf ]; then
        log "PKG|WARNING|Why are we doing this?" t
        log "{GEN,ERR}|WARNING|Package $tf not found in source $sd, creating." t
        processCmd " install -vm664 $devBase/sources/$tf $sd/$tf"
        return
    fi

    ext="${tf##*.}"
    log "PKG|INFO|Extension established: $ext" t
    log "PKG|INFO|Calling setCmdFileList." t
    setCmdFileList
    if [ $hasBuildDir -lt 1 ]; then
        buildDir=$sd/$sdn/build
        log "GEN|INFO|Checking if build dir: $buildDir exists." t
        if [ ! -d "$builDir" ]; then
            log "GEN|WARNING|Build directory flag set, but dir does not exist, creating..." t
            processCmd "install -vdm755 $buildDir"
            [ $? -gt 0 ] && log "{PKG,ERR}|ERROR|Error creating $buildDir." t && return 1
        fi
    else
        buildDir=$sd/$sdn
    fi
    log "PKG|INFO|buildDir set: $buildDir." t

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
        return 1
    fi
    log "PKG|INFO|unpackCmd set: $unpackCmd." t
    return 0
}

function unloadPkg {
    unset -v pkg sdnConf tf sdn hasBuildDir buildDir ld ext unpackCmd banner genConfigFile depcheckCmdFile preconfigCmdFile configCmdFile compileCmdFile checkCmdFile preInstallCmdFile installCmdFile preImplementCmdFile postImplementCmdFile cmdFileList preconfigCmd configCmd compileCmd checkCmd preInstallCmd installCmd preImplementCmd postImplementCmd autoInstallCmdList
    isImplemented=1
}

function unpack {
    log "{GEN,PKG}|INFO|Unpacking source code $tf" t

    if [ ! -f $sd/$tf ]; then
        log "{GEN,PKG,ERR}|FATAL|$tf not found." t
        return 1
    fi

    log "PKG|INFO|Running Cmd: $unpackCmd" t
    mPush $sd
    processCmd "${unpackCmd}"
    [ $? -gt 0 ] && log "{PKG,ERR}|ERROR|Error unpacking with $unpackCmd" t && return 1
    if [ $hasBuildDir == 0 ] && [ ! -d $sd/$sdn/build ]; then
        log "PKG|INFO|Creating build directory" t
        processCmd "install -olfs -glfs -vdm755 $sd/$sdn/build"
        [ $? -gt 0 ] && log "{PKG,ERR}|ERROR|Error creating build directory" t && return 1
    fi

    log "{GEN,PKG}|INFO|Done." t
    mPop
    return 0
}

function autoInstall {
    log "GEN|INFO|AutoInstall will be running the following tasks:"
    i=0
    while [[ $i < ${#autoInstallCmdList[@]} ]]; do
        echo "${autoInstallCmdList[$i]}"
        ((i++))
    done
    promptUser "Do you wanto start now?"
    read y
    case $y in
        [nN])
            return
            ;;
        [yY]|*)
            runAutoInstall
            [ $? -gt 0 ] && log "{GEN,ERR}|ERROR|Error during autoInstall." t && return 1
            ;;
    esac
}

function runAutoInstall {
    ii=0
    log "PKG|INFO|Starting auto install." t
    while [[ $ii < ${#autoInstallCmdList[@]} ]]; do
        f=${autoInstallCmdList[$ii]}
        ((ii++))
        log "GEN|INFO|Sourcing $f." true
        evalPrompt $f
        res=$?
        log "GEN|INFO|Came back from evalPrompt with $res" t
        [ $res -gt 0 ] && log "{PKG,ERR}|ERROR|Error sourcing $f. Aborting!" t && return 1
        if [ "$f" = "check" ]; then
            promptUser "Just finished checks, verify it. Do I keep going? Y/n"
            read t
            case $t in
                [Nn])
                    log "{PKG|ERR}|ERROR|User reported error. Aborting!" t
                    return 1
                    ;;
                [Yy]|*)
                    ((ii++))
                    continue
                    ;;
            esac
        fi

    done
    log "PKG|INFO|Auto install completed, all seems to be good." t
    return 0
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
                log "GEN|INFO|Using: $file" t
                pkg=$(basename $file)
                log "{GEN,PKG}|INFO|pkg seto $pkg" t
                if [ ! -f $sd/$pkg ]; then
                    log "{GEN,ERR}|FATAL|Could not find $pkg after finding it????" t
                    return 1
                fi
                break
                ;;
        esac
    done
    if [ ! -f $sd/$pkg ]; then
        log "GEN|WARNING|No package found for $pkg*." t
        return 1
    fi
}

function processCmd {
    local cmd=""
    for part in $@; do
        cmd=$cmd" "$part
    done
    log "GEN|INFO|Processing cmd: $cmd"
    if [[ $DEBUG = 0 ]]; then
        eval "$cmd >&${genLogFD} 2>&${errLogFD}"
    elif [[ $DEBUG = 1 ]]; then
        eval "$cmd > >(tee >(cat - >&${genLogFD})) 2> >(tee >(cat - >&${errLogFD}) >&2)"
    fi
    return $?
}

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

function promptUser {
COLOR="\e[37m"
echo -en $COLOR$1" : \e[0m"
}

function sourceScript {
    c=$1
    log "GEN|INFO|Sourcing: $c" t
    source $c
    res=$?
    log "GEN|INFO|Sourced $c returned: $res" t
    return $res
}

function cleanup {
    log "GEN|INFO|Cleaning up source file" t
    processCmd "rm -vfr $sdn"
    [ $? -gt 0 ] && log "{PKG,ERR}|ERROR|Error cleaning up." t && return 1
    return 0
}

function quitPkm {
    declare ret=0 ## Default exit value
    if [ $1 ]; then ret=$1; fi ## Override exit value
    unMountLfs
    [ $? -gt 0 ] && echo "ERROR with unMountLfs, CHECK YOUR SYSTEM." && ret=1

    log "GEN|INFO|Closing logs." t
    [ ${genLogFD} ] && exec {genLogFD}>&-
    [ ${pkgLogFD} ] && exec {pkgLogFD}>&-
    [ ${errLogFD} ] && exec {errLogFD}>&-

    unset genLogFile pkgLogFile errLogFile
    unset genLogFD pkgLogFD errLogFD

    if [ -f $devBase/var/run/pkm/pkm.lock ]; then
        log "GEN|INFO|Removing pkm lock." t
        sudo rm $devBase/var/run/pkm/pkm.lock
        [ $? -gt 0 ] && echo "Error removing lock." && exit $res
    fi
    if [[ ! "$2" = "" ]]; then
        echo "Quitting message: $2."
    fi

    exit $ret
}

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

function mPush {
    [ ! $1 ] && return 1
    processCmd "pushd $1"
    [ $? -gt 0 ] && quitPkm 1 "Error pushing $1 onto stack." || return 0
}

function mPop {
    processCmd "popd"
    [ $? -gt 0 ] && quitPkm 1 "Error poping directory of the stack" || return 0
}

function evalPrompt {
    case $1 in
        listcommands)
            listCommands
            ;;
        unpack)
            unpack
            return $?
            ;;
        depcheck)
            log "GEN|INFO|Running dependency check scripts" t
            sourceScript "${depcheckCmdFile}"
            return $?
            ;;
        preconfig)
            log "GEN|INFO|Running pre-config scripts" t
            if [ $hasBuildDir -lt 1 ]; then
                mPush $sd/$sdn
            else
                mPush $buildDir
            fi
            sourceScript "${preconfigCmdFile}"
            res=$?

            mPop
            return $res
            ;;
        config)
            log "GEN|INFO|Running config scripts" true
            mPush $buildDir
            sourceScript "${configCmdFile}"
            res=$?
            mPop
            return $res
            ;;
        compile)
            log "GEN|INFO|Running compile scripts" true
            mPush $buildDir
            sourceScript "${compileCmdFile}"
            res=$?
            mPop
            return $res
            ;;
        check)
            log "GEN|INFO|Running check scripts" true
            mPush $buildDir
            sourceScript "${checkCmdFile}"
            res=$?
            mPop
            return $res
            ;;
        preinstall)
            log "GEN|INFO|Running PreInstall scripts" true
            mPush $buildDir
            sourceScript "${preInstallCmdFile}"
            res=$?
            mPop
            return $res
            ;;
        install)
            log "GENINFO|Running install scripts" true
            mPush $buildDir
            sourceScript "${installCmdFile}"
            res=$?
            mPop
            return $res
            ;;
        preimplement)
            log "GEN|INFO|Running preImplement scripts" true
            mPush $buildDir
            sourceScript "${preImplementCmdFile}"
            res=$?
            mPop
            return $res
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
            quitPkm
            ;;
        ilsil)
            importLfsScriptedImplementLogs
            ;;
        *)
            log "GEN|INFO|Unknown command: $1" t
            return 1
            ;;
    esac

}

function prompt {
while true; do
promptUser "Input."
read -e command
evalPrompt $command
done
}

## Checking user parameters
for arg in "$@"
do
    case "$arg" in
        --updatePkgFromLocal)
            updatePkgFromLocal
            [ $? -gt 0 ] && echo "Error happen, check your installation." && quitPkm 1
            quitPkm 0
            ;;
        --updatePkm)
            updatePkm
            if [[ $? > 0 ]]; then
                echo "Error happen, check your installation."
                exit 1
            fi
            exit 0
    esac
done




singleton ## Ensure only one instance runs.
if [[ $? > 0 ]]; then
    exit 1
fi
log "NULL|INFO|Starting PKM" t
readConfig
startLog
startupCheck
prompt
