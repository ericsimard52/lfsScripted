#!/bin/bash

declare DEVBASE=`pwd`
declare CONFIGFILE="$DEVBASE/etc/pkm.conf"
declare LOGPATH="/var/log/pkm"
declare SD SDN SDNCONF PKG EXT HASBUILDDIR BUILDDIR CONFBASE WGETURL LFS LFSUSERHOME
declare -a PARTITIONDEV PARTITIONNAME PARTITIONMOUNT PARTITIONFS
declare UNPACKCMD
declare MAKEFLAGS
declare DEBUG=0
## Location and file descriptor of main & secondary log destination.
declare LOGFILE LOGFD
declare SLP="/var/log/pkm"
declare SECONDARYLOGPATH SECONDARYLOGFILE SECONDARYLOGFD 
declare SECONDARYLOGACTIVE=1
declare CMD
declare DEVMODE=0

# Config files
declare GENCONFIGFILE DEPCHECKCMDFILE PRECONFIGCMDFILE CONFIGCMDFILE COMPILECMDFILE CHECKCMDFILE
declare PREINSTALLCMDFILE INSTALLCMDFILE
declare -a CMDFILELIST AUTOINSTALLCMDLIST

function singleton {
    [ ! -d /var/run/pkm ] && sudo install -vdm 777 /var/run/pkm
    if [ -f /var/run/pkm/pkm.lock ]; then
        echo "Pkm is already running or has not quit properly, in that case, remove /var/run/pkm/pkm.lock" t
        return 1
    fi
    touch /var/run/pkm/pkm.lock
    [ $? -gt 0 ] && echo "Unable to create lock file. Ensure only 1 instance is running."

    # If we are lfs user, we assume installation is done and proceed as normal.
    declare usr=`whoami`
    if [[ $usr == "lfs" ]]; then
        echo "We are lfs, we assume this is a normal startup."
        return 0
    fi

    ## We are not lfs user, but if it exists, warn to run as lfs
    grep -q lfs < /etc/passwd
    if [[ $? == 0 ]] && [ $USER != "lfs" ]; then
        unset usr
        quitPkm 1 "Run this program as lfs user."
    fi
    unset usr

    ## We are not lfs user and it does not exists, install lfsScripted.
    readConfig
    startLog
    checkLfsUser
    [ $? -gt 0 ] && quitPkm 1 "Error with checkLfsUser"
    log "GEN|INFO|Installing lfsScripted into lfs home folder." t
    CMD=( sudo cp -fr $DEVBASE $LFSUSERHOME )
    processCmd
    [ $? -gt 0 ] && quitPkm 1 "Error copy $DEVBASE -> $LFSUSERHOME"

    checkPerm $LFSUSERHOME/lfsScripted
    [ $? -gt 0 ] && quitPkm 1 "Error in checkPerm $LFSUSERHOME/lfsScripted"
    echo "Su to lfs user, check pkm.conf and variable DEVBASE in pkm.sh"
    echo "Then su - lfs && cd lfsScripted && ./pkm.sh."
    quitPkm 0
}

## Copy all source script folders in etc into lfs installation.
## This command is only usefull when in development.
function updatePkgFromLocal {
    readConfig
    startLog
    log "GEN|INFO|Making backup of pkm.conf in $LFSUSERHOME" t
    CMD=( sudo cp -fv $LFSUSERHOME/lfsScripted/etc/pkm.conf $LFSUSERHOME/lfsScripted/etc/pkm.conf.bak )
    processCmd

    log "GEN|INFO|Copy source scripts to $LFSUSERHOME" t
    CMD=( sudo cp -frv ./etc/* $LFSUSERHOME/lfsScripted/etc/ )
    processCmd

    log "GEN|INFO|Restaure pkm.conf it got overwriten." t
    CMD=( sudo mv -v $LFSUSERHOME/lfsScripted/etc/pkm.conf.bak $LFSUSERHOME/lfsScripted/etc/pkm.conf )
    processCmd

    checkPerm $LFSUSERHOME/lfsScripted
    [ $? -gt 0 ] && quitPkm 1 "Error with checkPerm in updatePkgFromLocal"
    checkPerm $LFSUSERHOME/lfsScripted/etc
    [ $? -gt 0 ] && quitPkm 1 "Error with checkPerm in updatePkgFromLocal"
    return 0
}

## Similar to uploadPkgFromLocal this function is called from the CLI arg passed to pkm.sh
## Used in development to update lfs version of pkm.sh
function updatePkm {
    readConfig
    startLog
    log "GEN|INFO|Installing pkm.sh into lfs home." t
    CMD=( sudo cp -vf ./pkm.sh $LFSUSERHOME/lfsScripted )
    processCmd
    [ $? -gt 0 ] && quitPkm 1 "Error with cp pkm.sh to lfs"
    sudo sed -i -e 's:Git/::g' $LFSUSERHOME/lfsScripted/pkm.sh
    sudo sed -i -e 's:tech:lfs:g' $LFSUSERHOME/lfsScripted/etc/pkm.conf
    checkPerm $LFSUSERHOME/lfsScripted/pkm.sh
    [ $? -gt 0 ] && quitPkm 1 "Error with checkPerm in updatePkm."
    quitPkm 0
}

function startLog {
    [ ! -d $LOGPATH ] && sudo install -vdm 777 $LOGPATH
    if [ ! -f $LOGPATH/$LOGFILE ]; then
        log "NULL|INFO|Creating $LOGFILE" t
        touch $LOGPATH/$LOGFILE
        chmod 666 -v $LOGPATH/$LOGFILE
    fi
    log "NULL|INFO|Creating file descriptor for logs" t
    exec {LOGFD}>$LOGPATH/$LOGFILE
}

###
# Read config file stored in $CONFIGFILE
###
function readConfig {
    log "NULL|INFO|Reading configuration file." t
    if [ ! -f $CONFIGFILE ]; then
        log "NULL|ERROR|Configuration file: $configfile is missing." t
        quitPkm 1
    fi
    while read -r line; do
        IFS=':' read -ra PARAM <<< "$line"
        case "${PARAM[0]}" in
            debug)
                DEBUG=${PARAM[1]}
                log "NULL|INFO|Set param DEBUG:$DEBUG" t
                ;;
            sd)
                SD=${PARAM[1]}
                log "NULL|INFO|Set param sd:$SD" t
                ;;
            confBase)
                CONFBASE=${PARAM[1]}
                log "NULL|INFO|Set param confBase:$CONFBASE" t
                ;;
            MAKEFLAGS)
                MAKEFLAGS=${PARAM[1]}
                log "NULL|INFO|Set param MAKEFLAGS:$MAKEFLAGS" t
                ;;
            bypassImplement)
                BYPASSIMPLEMENT=${PARAM[1]}
                log "NULL|INFO|Set param bypassImplement:$bypassImplement" t
                ;;
            logFile)
                LOGFILE=${PARAM[1]}
                log "NULL|INFO|Set param genLogFile:$LOGFILE" t
                ;;
            partitionDev)
                PARTITIONDEV=(${PARAM[1]})
                log "NULL|INFO|Set param partitionDev:$PARTITIONDEV" t
                ;;
            partitionName)
                PARTITIONNAME=(${PARAM[1]})
                log "NULL|INFO|Set param partitionName:$PARTITIONNAME" t
                ;;
            partitionMount)
                PARTITIONMOUNT=(${PARAM[1]})
                log "NULL|INFO|Set param partitionMount:$PARTITIONMOUNT" t
                ;;
            partitionFs)
                PARTITIONFS=(${PARAM[1]})
                log "NULL|INFO|Set param partitionFs:$PARTITIONFS" t
                ;;
            LFS)
                LFS=${PARAM[1]}
                log "NULL|INFO|Set param LFS:$LFS" t
                ;;
            lfsUserHome)
                LFSUSERHOME=${PARAM[1]}
                log "NULL|INFO|Set param lfsUserHome:$LFSUSERHOME" t
                ;;
            devMode)
                DEVMODE=${PARAM[1]}
                log "NULL|INFO|Set param devMode:$DEVMODE" t
                ;;
            "#") continue;;
            *) continue;;
        esac
        unset IFS
    done < $CONFIGFILE
    export MAKEFLAGS
    log "NULL|INFO|Done reading config file." t
}

function mountLfs {
    log "GEN|INFO|Checking mountpoint." t
    if [ ! -d $LFS ]; then
        log "GEN|ERROR|Mount point $LFS does not exist. Creating." t
        CMD=( sudo mkdir -pv $LFS )
        processCmd
        [ $? -gt 0 ] && quitPkm 1 "GEN|FATAL|Error creating $LFS."
    fi
    log "GEN|INFO|Mounting partitions." t
    x=0
    pl=${#PARTITIONNAME[@]}
    log "GEN|INFO|Got $pl partition to mount." t
    while [ $x -lt $pl ]; do
        pn=${PARTITIONNAME[$x]}
        pm=${PARTITIONMOUNT[$x]}
        pd=${PARTITIONDEV[$x]}
        pf=${PARTITIONFS[$x]}

        if [[ "$pn" = "swap" ]]; then
            if [[ `grep /dev/ < <(sudo swapon -s) |wc -l` < 1 ]]; then
                log "GEN|INFO|Found swap partition, Ativating." t
                CMD=( sudo /sbin/swapon -v $pd )
                processCmd
                [ $? -gt 0 ] && quitPkm 1 "Error activating swap"
                log "GEN|WARNING|Swap should be last to mount, if not, next partition will not be mounted." t
                return 0
            else
                log "GEN|INFO|Swap already active, skipping." t
                return 0
            fi
        fi

        if [ ! -d $LFS$pm ]; then
            log "GEN|WARNING|$LFS$pm does not exists, creating." t
            CMD=( sudo mkdir -pv $LFS$pm )
            processCmd
            [ $? -gt 0 ] && quitPkm 1 "$LFS$pm does not exists and unable to create."
        fi
        log "GEN|INFO|Check if $pd mounted on $pm" t
        if [[ `grep "$pd on $pm" < <(mount) | wc -l` < 1 ]]; then
            log "GEN|INFO|Mounting $pd on $pm" t
            CMD=( sudo mount -v -t $pf $pd $LFS$pm )
            processCmd
            [ $? -gt 0 ] && quitPkm 1 "Unable to mount $pd on $pm"
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
    pl=${#PARTITIONNAME[@]}
    log "GEN|INFO|Got $pl partition to unmount." t
    while [ $x -lt $pl ]; do
        pn=${PARTITIONNAME[$x]}
        pm=${PARTITIONMOUNT[$x]}
        pd=${PARTITIONDEV[$x]}
        pf=${PARTITIONFS[$x]}

        if [[ "$pn" = "swap" ]]; then
            log "GEN|WARN|Not turning off swap, there is a host system active." t
            break
        fi

        log "GEN|INFO|Check if $pd mounted on $pm" t
        if [[ `grep "$pd on $pm" < <(mount) | wc -l` > 0 ]]; then
            log "GEN|INFO|Unmounting $pd from $pm" t
            CMD=( sudo umount -v $pd )
            processCmd
            [ $? -gt 0 ] && log "{GEN,ERR}|ERROR|Error unmounting $pd, check manually." t
        else
            log "GEN|INFO|$pd not mounted." t
        fi
        ((x++))
    done
    return 0
}

function checkSources {
    log "GEN|INFO|Checking if source directory $SD exists." t
    if [ ! -d $SD ]; then
        log "GEN|WARNING|Source directory $SD does not exists, creating." t
        CMD=( sudo mkdir -vp $SD )
        processCmd
        [ $? -gt 0 ] && quitPkm 1 "Unable to create $SD"
        CMD=( sudo chmod -v a+wt $SD )
        processCmd
        [ $? -gt 0 ] && log "GEN|WARNING|chmod a+wt on $SD reported failure, check manually." t
    fi
    log "GEN|INFO|Done." t

    log "GEN|INFO|Do we have wget.list?" t
    if [ ! -f $CONFBASE/wget.list ]; then
        if [ -f $DEVBASE/etc/wget.list ]; then
            log "NULL|INFO|Taking local wget.list" t
            CMD=( sudo cp -v $DEVBASE/etc/wget.list $CONFBASE/ )
            processCmd
            [ $? -gt 0 ] && return 1
        else
            log "GEN|WARNING|wget.list not found, fetching." t
            CMD=( sudo wget -v -O $CONFBASE/wget.list -v "http://www.linuxfromscratch.org/lfs/view/stable/wget-list" )
            processCmd
            [ $? -gt 0 ] && quitPkm 1 "Unable to fetch wget.list. I will crash if I don't quit now"
        fi
    fi
    log "GEN|INFO|Checking source packages." t
    for line in `cat $CONFBASE/wget.list`; do
        fn=$(basename $line)
        log "GEN|INFO|Checking for $fn" t
        if [ ! -f $SD/$fn ]; then
            log "GEN|INFO|$fn not found, fetching." t
            CMD=( sudo wget -v $line -O $SD/$fn )
            processCmd
            if [ $? -gt 0 ]; then
                log "GEN|ERROR|Unable to fetch $fn." t
                [ -e $SD/$fn ] && CMD=( rm -v $SD/$fn ) && processCmd
            fi

        fi
    done

    log "GEN|INFO|Do we have md5sums?" t
    if [ ! -f $CONFBASE/md5sums ]; then
        if [ -f $DEVBASE/etc/md5sums ]; then
            log "NULL|INFO|Taking local wget.list" t
            CMD=( sudo cp -v $DEVBASE/etc/md5sums $CONFBASE/ )
            processCmd
            [ $? -gt 0 ] && return 1
        else

            log "GEN|WARNING|md5sums not found, fetching." t
            CMD=( sudo wget -v -O $CONFBASE/md5sums -v "http://www.linuxfromscratch.org/lfs/view/stable/md5sums" )
            processCmd
            [ $? -gt 0 ] && log "GEN|WARNING|Unable to fetch md5sums check list. Unsure how the program will behave at check time." t
        fi
    fi

    # Touch dummy pkg
    declare -a _dummyPkgList=('dummy.tar.xz')
    declare _dp
    for _dp in ${_dummyPkgList[@]}; do
        if [ ! -e $SD/$_dp ]; then
            log "GEN|INFO|Creating dummy package $_dp" t
            CMD=( sudo touch $SD/$_dp )
            processCmd
            [ $? -gt 0 ] && log "GEN|WARNING|Unable to create $_dp dummy pkg. Also, make this better. Dummy Package will be needed more often." t
        fi
    done
    unset _dummyPkgList _dp
    log "GEN|INFO|Checking md5." t
    mPush $SD
    CMD=( sudo cp $CONFBASE/md5sums ./ )
    processCmd
    CMD=( sudo md5sum -c ./md5sums )
    processCmd
    if [ $? -gt 0 ]; then
        mPop
        CMD=( sudo rm $CONFBASE/md5sums )
        processCmd
        quitPkm 1 "Source md5sum check failed. Check logs for details."
    fi
    mPop
    return 0
}

function checkLfsUser {
    log "GEN|INFO|Checking LFS group & user." t
    grep -q lfs < /etc/group
    if [[ $? > 0 ]]; then
        log "GEN|WARNING|lfs group does not exists, creating." t
        CMD=( sudo groupadd lfs )
        processCmd
        [ $? -gt 0 ] && quitPkm 1 "Unable to create lfs group"
    fi

    grep -q lfs < /etc/passwd
    if [[ $? > 0 ]];then
        log "GEN|WARNING|lfs user not found. Fixing." t
        CMD=( sudo useradd -s /bin/bash -g lfs -d $LFSUSERHOME -m -k $DEVBASE/etc/lfsHomeSkel lfs )
        processCmd
        [ $? -gt 0 ] && quitPkm 1 "Unable to add lfs user."

        log "GEN|INFO|Set password for lfs user." t
        sudo passwd lfs
        [ $? -gt 0 ] && quitPkm 1 "Error setting lfs password"
    fi
    return 0

}

function checkStruct {
    log "GEN|INFO|Checking $LFS/tools." t
    if [ ! -d $LFS/tools ]; then
        log "GEN|WARNING|$LFS/tools does not exists, creating." t
        CMD=( sudo mkdir -pv $LFS/tools )
        processCmd
        [ $? -gt 0 ] && quitPkm 1 "Error create $LFS/tools."
    fi
    if [ ! -h /tools ]; then
        log "GEN|WARNING|/tools link does not exists, creating." t
        CMD=( sudo ln -sv $LFS/tools / )
        processCmd
        [ $? -gt 0 ] && quitPkm 1 "Error creating /tools link."
    fi
    return 0
}

function checkPerm {
    log "GEN|INFO|Checking permission and ownership" t
    declare -a toCheck
    declare res=0
    if [ $1 ]; then
        toCheck=($1)
    else
        toCheck=($LFS/tools $SD $DEVBASE/etc $DEVBASE/var $LFSUSERHOME)
    fi
    for d in ${toCheck[@]}; do
        log "GEN|INFO|Check permissions and owners of $d" t
        if [ -d $d ]; then
            for file in $d; do
                user=`stat -c %U $file`
                log "GEN|INFO|Owner of $file: $user"
                if [[ ! "$user" = "lfs" ]]; then
                    log "GEN|INFO|Fixing ownership of $file." t
                    CMD=( sudo chown -vR lfs:lfs $file )
                    processCmd
                    [ $? -gt 0 ] && log "GEN|ERROR|Error changing ownership of $file" t && res=1
                    CMD=( sudo chmod g+w -vR $file )
                    processCmd
                    [ $? -gt 0 ] && log "GEN|ERROR|Error changing mode of $file" t && res=1
                fi

            done
        elif [ -f $d ]; then
            user=`stat -c %U $d`
            log "GEN|INFO|Owner of $file: $user"
            if [[ ! "$user" = "lfs" ]]; then
                log "GEN|INFO|Fixing ownership of $file." t
                CMD=( sudo chown -v lfs:lfs $file )
                processCmd
                [ $? -gt 0 ] && log "GEN|ERROR|Error changing ownership of $file" t && res=1
                CMD=( sudo chmod g+w -v $file )
                processCmd
                [ $? -gt 0 ] && log "GEN|ERROR|Error changing mode of $file" t && res=1
            fi
        fi
    done
    return $res
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
    CMD=( command -v $1 )
    processCmd
    [ $? -gt 0 ] && return 1 || return 0
}

function checkLibInstalled {
    CMD=( sudo ldconfig -p '|' grep $1 )
    processCmd
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
\e[34msd: \e[32m$SD
\e[34msdn: \e[32m$SDN
\e[34mtf: \e[32m$TF
\e[34mSDNCONF: \e[32m$SDNCONF
\e[34mext: \e[32m$EXT
\e[34mhasBuildDir: \e[32m$HASBUILDDIR
\e[34mMAKEFLAGS: \e[32m$MAKEFLAGS
\e[34mbuildDir: \e[32m$BUILDDIR
\e[34mLFS: \e[32m$LFS
\e[34mconfigFile: \e[32m$CONFIGFILE
\e[34mconfBase: \e[32m$CONFBASE
\e[34mgenLog: \e[32m$GENLOGFILE
\e[34mgenLogFD: \e[32m$GENLOGFD
\e[34mpkgLog: \e[32m$PKGLOGFILE
\e[34mpkgLogFD: \e[32m$PKGLOGFD
\e[34mimpLog: \e[32m$IMPLOGFILE
\e[34mimpLogFD: \e[32m$IMPLOGFD
\e[34merrLog: \e[32m$ERRLOGFILE
\e[34merrLogFD: \e[32m$ERRLOGFD
\e[34mNEXTPKG: \e[32m$NEXTPKG
\e[0m\n"
}

function log {
    ## Format
    ## log "LEVEL|..." PRINTOSTDOUT DEBUGONLYMESSAGE
    ## log "INFO|..." t = print to stdout
    ## log "INFO|..." t t = print to stdout only if debug=1
    ## log "INFO|..." - t = process only if debug=1 and send only to LOGFILE
    ## Messages are always sent to LOGFILE

    if [ $3 ] && [[ $DEBUG = 0 ]]; then # if 3 param set, we process msg only if debug is 1
        return
    fi
    declare _LEVEL _COLOR _MSG _M _LOGMSG _CALLER _CALLERLOG

    MSGEND=" \e[0m" ## Clear all formatting

    ## Setting up file descriptor destination
    IFS='|' read -ra PARTS <<< $1
    ### Set color formatting
    case "${PARTS[1]}" in
        INFO)
            _LEVEL=INFO
            _COLOR="\e[39m"
            ;;
        WARNING)
            _LEVEL=WARNING
            _COLOR="\e[33m"
            ;;
        ERROR)
            _LEVEL=ERROR
            _COLOR="\e[31m"
            ;;
        FATAL)
            _LEVEL=FATAL
            _COLOR="\e[31m"
            ;;
    esac

    ### Append message provided by caller
    _M="${PARTS[2]}"
    if [[ "$_M" = "" ]]; then
        return
    fi

    if [ $SDN ]; then
        _CALLER="\e[32m"$PKG"\e[0m "
        _CALLERLOG=$PKG
    else
        _CALLERLOG="NONE"
        _CALLER="\e[32mNONE\e[0m "
    fi
    _MSG=$_COLOR$_LEVEL" - "$_CALLER":"$_COLOR$_M$_MSGEND ## Full message string
    _LOGMSG=$_LEVEL" - "$_CALLERLOG":"$_M$_MSGEND

    # Printo stdOut
    if [ $SECONDARYLOGACTIVE -eq 0 ]; then
        [ ${SECONDARYLOGFD} ] && echo $_LOGMSG >&${SECONDARYLOGFD}
    else
        [ ${LOGFD} ] && echo $_LOGMSG >&${LOGFD}
    fi
    if [[ $2 ]] && [[ "$2" = "t" ]]; then # if t after message, print to stdout
        echo -e $_MSG
    fi


    unset IFS _FDs _LEVEL _COLOR _MSG _M _MSGEND _LOGMSG _CALLER _CALLERLOG
    return
}

function loadPkg {
    if [[ $PKG ]]; then
        log "GEN|INFO|Unloading $PKG from memory." t
        unloadPkg
    fi

    if [ $1 ]; then
        PKG=$1
    else
        promptUser "Which package?"
        read PKG
    fi
    if [[ "$PKG" == "" ]]; then
        log "ERR|INFO|Empty package provided..."
        return 1
    fi
    if [ ! -d $CONFBASE/$PKG ]; then
        declare -a foundFiles
        for file in `find $CONFBASE -maxdepth 1 -type d -iname "$PKG*"`; do
            promptUser "FoundFiles: $file\n Use it? Y/n"
            read u
            case $u in
                [nN])
                    continue
                    ;;
                [yY]|*)
                    log "GEN|INFO|Using: $file" t
                    PKG=$(basename $file)
                    if [ ! -d $CONFBASE/$PKG ]; then
                        log "ERR|FATAL|Could not find $PKG after finding it????" t
                        return 1
                    fi
                    break
                    ;;
            esac
        done
        if [ ! -d $CONFBASE/$PKG ]; then
            log "ERR|FATAL|No package found for $PKG." t
            return 1
        fi
    fi
    SDNCONF=$CONFBASE/$PKG
    log "PKG|INFO|SDNCONF set: $SDNCONF." t
    GENCONFIGFILE="$SDNCONF/$PKG.conf"
    log "PKG|INFO|genConfigFile set: $GENCONFIGFILE." t
    if [ ! -f $GENCONFIGFILE ]; then
        log "ERR|ERROR|Package general config file missing" t
        return 1
    fi

    log "PKG|INFO|Reading config file into variables" t
    while read -r line; do
        IFS=':' read -ra PARAM <<< "$line"
        case "${PARAM[0]}" in
            tf)
                log "PKG|INFO|tf: ${PARAM[1]}" t
                TF=${PARAM[1]}
                ;;
            sdn)
                log "PKG|INFO|sdn: ${PARAM[1]}" t
                SDN=${PARAM[1]}
                ;;
            sd)
                log "PKG|INFO|sd: ${PARAM[1]}" t
                SD=${PARAM[1]}
                ;;
            hasBuildDir)
                log "PKG|INFO|hasBuildDir: ${PARAM[1]}" t
                HASBUILDDIR=${PARAM[1]}
                ;;
            bypassImplement)
                log "PKG|INFO|bypassImplement: ${PARAM[1]}" t
                BYPASSIMPLEMENT=${PARAM[1]}
                ;;
            tasks)
                log "PKG|INFO|Loading tasks list." t
                IFS=',' read -ra TASK <<< "${PARAM[1]}"
                x=0
                while [[ $x < ${#TASK[@]} ]]; do
                    log "PKG|INFO|Adding ${TASK[$x]}." t
                    AUTOINSTALLCMDLIST+=(${TASK[$x]})
                    ((x++))
                done
                IFS=':'
                ;;
            makeflags)
                log "PKG|INFO|Chaning makeflags" t
                MAKEFLAGS=${PARAM[1]}
                ;;
            debug) DEBUG=${PARAM[1]};;
            nextPkg) NEXTPKG=${PARAM[1]};;
            *) log "{GEN,ERR}|ERROR|Unknow params: ${PARAMS[1]}" t;;
        esac
        unset IFS
    done < $GENCONFIGFILE


    log "GEN|INFO|Check if source package exists: $SD/$TF" t
    # Check if source package exists
    ## What is this
    if [ ! -f $SD/$TF ]; then
        log "PKG|WARNING|Package not found, something is wrong." t
        return 1
    fi

    EXT="${TF##*.}"
    log "PKG|INFO|Extension established: $EXT" t
    log "PKG|INFO|Calling setCmdFileList." t
    setCmdFileList
    if [ $HASBUILDDIR -lt 1 ]; then
        BUILDDIR=$SD/$SDN/build
        log "GEN|INFO|Checking if build dir: $BUILDDIR exists." t
        if [ ! -d "$BUILDIR" ]; then
            log "GEN|WARNING|Build directory flag set, but dir does not exist, creating..." t
            CMD=( install -vdm755 $BUILDDIR )
            processCmd
            [ $? -gt 0 ] && log "{PKG,ERR}|ERROR|Error creating $BUILDDIR." t && return 1
        fi
    else
        BUILDDIR=$SD/$SDN
    fi
    log "PKG|INFO|buildDir set: $BUILDDIR." t

    # Secondary log setup
    SECONDARYLOGPATH=$SLP/$SDN
    [ ! -d $SECONDARYLOGPATH ] && CMD=( install -vdm 777 $SECONDARYLOGPATH ) && processCmd
    # Adjusting the unpack commands
    log "GEN|INFO|Adjusting unpack command for $EXT." t
    if [[ "$EXT" == "xz" ]]; then
        UNPACKCMD=( tar xvf $TF )
    elif [[ "$EXT" == "gz" ]]; then
        UNPACKCMD=( tar xvfz $TF )
    elif [[ "$EXT" == "gzip" ]]; then
        UNPACKCMD=( tar xvfz $TF )
    elif [[ "$EXT" == "bz2" ]]; then
        UNPACKCMD=( tar xvfj $TF )
    elif [[ "$EXT" == "tgz" ]]; then
        UNPACKCMD=( tar xvfz $TF )
    else
        log "ERR|FATAL|Unknown package unpack method." true
        return 0
    fi
    log "PKG|INFO|unpackCmd set: $UNPACKCMD." t
    return 0
}

function unloadPkg {
    unset -v PKG SDNCONF TF SDN HASBUILDDIR BUILDDIR LD EXT UNPACKCMD BANNER GENCONFIGFILE DEPCHECKCMDFILE PRECONFIGCMDFILE CONFIGCMDFILE COMPILECMDFILE CHECKCMDFILE PREINSTALLCMDFILE INSTALLCMDFILE PREIMPLEMENTCMDFILE POSTIMPLEMENTCMDFILE CMDFILELIST PRECONFIGCMD CONFIGCMD COMPILECMD CHECKCMD PREINSTALLCMD INSTALLCMD PREIMPLEMENTCMD POSTIMPLEMENTCMD AUTOINSTALLCMDLIST NEXTPKG
    SECONDARYLOGPATH=$SLP
    SECONDARYLOGACTIVE=1
    isImplemented=1

}

function unpack {
    log "{GEN,PKG}|INFO|Unpacking source code $TF" t

    if [ ! -f $SD/$TF ]; then
        log "{GEN,PKG,ERR}|FATAL|$TF not found." t
        return 1
    fi
    printf -v cmd_str '%q ' "${UNPACKCMD[@]}"
    log "PKG|INFO|Running Cmd: $cmd_str" t
    mPush $SD

    if [ $DEBUG -eq 1 ]; then
        if [ $SECONDARYLOGACTIVE -eq 0 ]; then
            "${UNPACKCMD[@]}" >&${SECONDARYLOGFD} 2>&${SECONDARYLOGFD}
        else
            "${UNPACKCMD[@]}" >&${LOGFD} 2>&${LOGD}
        fi
    elif [ $DEBUG -eq 0 ]; then
        if [ $SECONDARYLOGACTIVE -eq 0 ]; then
            "${UNPACKCMD[@]}" 2>&1 | tee >( cat >&${SECONDARYLOGFD} )
        else
            "${UNPACKCMD[@]}" 2>&1 | tee >( cat >&${LOGFD} 2>&1 )
        fi
    fi
    if [ $? -gt 0 ]; then
        log "GEN|ERROR|Error processcing cmd $@" t
        return 1
    fi

    if [ $HASBUILDDIR == 0 ] && [ ! -d $SD/$SDN/build ]; then
        log "PKG|INFO|Creating build directory" t
        CMD=( install -olfs -glfs -vdm755 $SD/$SDN/build )
        processCmd
        [ $? -gt 0 ] && log "{PKG,ERR}|ERROR|Error creating build directory" t && return 1
    fi

    log "{GEN,PKG}|INFO|Done." t
    mPop
    return 0
}

function autoInstall {
    log "GEN|INFO|AutoInstall will be running the following tasks:"
    i=0
    while [[ $i < ${#AUTOINSTALLCMDLIST[@]} ]]; do
        echo "${AUTOINSTALLCMDLIST[$i]}"
        ((i++))
    done
    promptUser "Do you wanto start now?"
    read y
    case $y in
        [nN])
            return 0
            ;;
        [yY]|*)
            runAutoInstall
            [ $? -gt 0 ] && log "{GEN,ERR}|ERROR|Error during autoInstall." t && return 1
            ;;
    esac
    return 0
}

function runAutoInstall {
    ii=0
    log "PKG|INFO|Starting auto install." t
    while [[ $ii < ${#AUTOINSTALLCMDLIST[@]} ]]; do
        f=${AUTOINSTALLCMDLIST[$ii]}
        ((ii++))
        log "GEN|INFO|Sourcing $f." true
        evalPrompt $f
        [ $? -gt 0 ] && log "{PKG,ERR}|ERROR|Error sourcing $f. Aborting!" t && return 1
    done
    log "PKG|INFO|Auto install completed, all seems to be good." t
    return 0
}

function searchPkg {
    # If we can't file the package (source tar), we do a search for the term provided by the user.
    declare -a foundFiles
    for file in `find $SD -maxdepth 1 -type f -iname "$1*"`; do
        promptUser "FoundFiles: $file\n Use it? Y/n"
        read u
        case $u in
            [nN])
                continue
                ;;
            [yY]|*)
                log "GEN|INFO|Using: $file" t
                PKG=$(basename $file)
                log "{GEN,PKG}|INFO|pkg seto $PKG" t
                if [ ! -f $SD/$PKG ]; then
                    log "{GEN,ERR}|FATAL|Could not find $PKG after finding it????" t
                    return 1
                fi
                break
                ;;
        esac
    done
    if [ ! -f $SD/$PKG ]; then
        log "GEN|WARNING|No package found for $PKG*." t
        return 1
    fi
}

function processCmd {
    printf -v cmd_str '%q ' "${CMD[@]}"
    log "GEN|INFO|Processing cmd: $cmd_str" t
    eval "tput sgr0"
    if [ $DEBUG -eq 1 ]; then
        if [ $SECONDARYLOGACTIVE -eq 0 ]; then
            "${CMD[@]}" >&${SECONDARYLOGFD} 2>&${SECONDARYLOGFD}
        else
            "${CMD[@]}" >&${LOGFD} 2>&${LOGFD}
        fi
        if [ $? -gt 0 ]; then
            log "GEN|ERROR|Error processcing $cmd_str" t
            unset CMD
            return 1
        fi

    elif [ $DEBUG -eq 0 ]; then
        if [ $SECONDARYLOGACTIVE -eq 0 ]; then
            "${CMD[@]}" 2>&1 | tee >( cat >&${SECONDARYLOGFD} )
        else
            "${CMD[@]}" 2>&1 | tee >( cat >&${LOGFD} 2>&1 )
        fi
        if [ ${PIPESTATUS[0]} -gt 0 ]; then
            log "GEN|ERROR|Error processcing $cmd_str" t
            unset CMD
            return 1
        fi

    fi
    unset CMD

    if [ $DEVMODE -eq 0 ]; then
        promptUser "\e[31mDevmode is on.\e[0m Review previous commands: \e[93m$cmd_str\e[0m. Continue? Y/n"
        read DU
        case $DU in
            n|N)
                return 1
                ;;
        esac
    fi
    return 0

}

function promptUser {
    COLOR="\e[37m"
    echo -en $COLOR$1" : \e[0m"
}

function sourceScript {
    c=$1
    log "GEN|INFO|Sourcing: $c" t
    source $c
    [ $? -gt 0 ] && log "{GEN,ERR}|ERROR|Failed." t && return 1
    log "GEN|INFO|Success." t
    return 0
}

function cleanup {
    log "GEN|INFO|Cleaning up source file $SD/$SDN" t
    CMD=( rm -vfr $SD/$SDN )
    processCmd
    [ $? -gt 0 ] && log "{PKG,ERR}|ERROR|Error cleaning up." t && return 1
    return 0
}

function quitPkm {
    ## First log exit message if present
    if [ -n "$2" ]; then
        log "GEN|WARNING|Exist Message received: $2"
    fi
    declare ret=0 ## Default exit value
    if [ $1 ]; then ret=$1; fi ## Override exit value

    [ $? -gt 0 ] && echo "ERROR with unMountLfs, CHECK YOUR SYSTEM." && ret=1

    log "GEN|INFO|Closing logs." t
    [ ${LOGFD} ] && exec {LOGFD}>&-

    unset LOGFILE
    unset LOGFD

    if [ $SECONDARYLOGACTIVE -eq 0 ]; then
       closeSecondaryLog
    fi
    if [ -f /var/run/pkm/pkm.lock ]; then
        log "GEN|INFO|Removing pkm lock." t
        sudo rm /var/run/pkm/pkm.lock
        [ $? -gt 0 ] && echo "Error removing lock." && exit $res
    fi
    if [[ ! "$2" = "" ]]; then
        echo "Quitting message: $2."
    fi

    exit $ret
}

function setCmdFileList {
    log "GEN|INFO|Setting up command files list." true
    if [[ "$SDN" = "" ]]; then
        log "{GEN,ERR}|ERROR|SDN is not set." true
        return 1
    fi
    if [ "$SDNCONF" == "" ]; then
        log "{GEN,ERR}|ERROR|SDNCONF not set." true
        return 1
    fi

    DEPCHECKCMDFILE=$SDNCONF/depcheck
    PRECONFIGCMDFILE=$SDNCONF/preconfig
    CONFIGCMDFILE=$SDNCONF/config
    COMPILECMDFILE=$SDNCONF/compile
    CHECKCMDFILE=$SDNCONF/check
    PREINSTALLCMDFILE=$SDNCONF/preinstall
    INSTALLCMDFILE=$SDNCONF/install
    PREIMPLEMENTCMDFILE=$SDNCONF/preimplement
    POSTIMPLEMENTCMDFILE=$SDNCONF/postimplement
    CMDFILELIST=(
        $DEPCHECKCMDFILE
        $PRECONFIGCMDFILE
        $CONFIGCMDFILE
        $COMPILECMDFILE
        $CHECKCMDFILE
        $PREINSTALLCMDFILE
        $INSTALLCMDFILE
        $PREIMPLEMENTCMDFILE
        $POSTIMPLEMENTCMDFILE
    )
    return 0
}

function listTask {
    i=0
    last=${#AUTOINSTALLCMDLIST[@]}
    ((last--))

    while [[ $i < ${#AUTOINSTALLCMDLIST[@]} ]]; do
        [ $i -eq $last ] && echo -n "${AUTOINSTALLCMDLIST[$i]}" || echo -n "${AUTOINSTALLCMDLIST[$i]}, "
        ((i++))
    done
    echo ""
}

function mPush {
    [ ! $1 ] && return 1
    pushd $1 > /dev/null 2>&${LOGFD}
    [ $? -gt 0 ] && quitPkm 1 "Error pushing $1 onto stack." || return 0
}

function mPop {
    popd > /dev/null 2>&${LOGFD}
    [ $? -gt 0 ] && quitPkm 1 "Error poping directory of the stack" || return 0
}

function runAutoBuildTmpToolChain {
    bsrc=$DEVBASE/etc/autoBuildTmpToolChain/list
    [ ! -f $bsrc ] && log "{GEN,ERR}|ERROR| autoBuildTempToolChain directory not present et $DEVBASE/etc" t && return 1
    declare -a pkglist
    while read -r bline; do
        pkglist+=($bline)
    done < $bsrc
    for item in ${pkglist[@]}; do
        log "GEN|INFO|Loading $item" t
        loadPkg $item
        [ $? -gt 0 ] && log "GEN|ERR|Error load $item" t && return 1
        runAutoInstall
        [ $? -gt 0 ] && log "GEN|ERR|Error with autoinstall of $item" t && return 1
        log "GEN|INFO|Sourcing $item succesful." t
        unloadPkg
    done
    log "GEN|INFO|DONE BUIL TEMP" t
    return 0
}

function setupSecondaryLog {
    log "NULL|INFO|Setting up secondary log." t
    if [ ! $1 ]; then
       log "NULL|WARNING|Call to set secndary log, no parameters provided." t
       return 1
    fi
    SECONDARYLOGFILE=$1
    if [ ! -e $SECONDARYLOGPATH/$SECONDARYLOGFILE ]; then
       log "NULL|INFO|$SECONDARYLOGFILE does not exists. Creating." t
       CMD=( touch $SECONDARYLOGPATH/$SECONDARYLOGFILE )
       processCmd
       CMD=( chmod 666 $SECONDARYLOGPATH/$SECONDARYLOGFILE )
       processCmd
    fi
    exec {SECONDARYLOGFD}>$SECONDARYLOGPATH/$SECONDARYLOGFILE
    if [ $? -gt 0 ]; then
        log "NULL|ERROR|Error setting up file descriptor for $SECONDARYLOGPATH/$SECONDARYLOGFILE"
        return 1
    fi
    log "NULL|INFO|Secondary log activated. All log will go in $SECONDARYLOGPATH/$SECONDARYLOGFILE." t
    SECONDARYLOGACTIVE=0
    return 0
}

function closeSecondaryLog {
    log "NULL|INFO|Closing secondary log." t
    [ ${SECONDARYLOGFD} ] && exec {SECONDARYLOGFD}>&-
    if [ $? -gt 0 ]; then
        log "NULL|ERROR|Error closing file descriptor: for $SECONDARYLOGPATH/$SECONDARYLOGFILE"
        return 1
    fi
    SECONDARYLOGACTIVE=1
    SECONDARYLOGFILEPATH=$SLP
    unset SECONDARYLOGFILE
    log "NULL|INFO|Secondary log deactivated." t
    return 0
}

function evalPrompt {
    case $1 in
        listcommands)
            listCommands
            ;;
        unpack)
            setupSecondaryLog "unpack.log"
            unpack
            _r=$?
            closeSecondaryLog
            return $_r
            ;;
        depcheck)
            setupSecondaryLog "depcheck.log"
            log "GEN|INFO|Running dependency check scripts" t
            sourceScript "${DEPCHECKCMDFILE}"
            _r=$?
            closeSecondaryLog
            return $_r
            ;;
        preconfig)
            setupSecondaryLog "preconfig.log"
            log "GEN|INFO|Running pre-config scripts" t
            if [ $HASBUILDDIR -lt 1 ]; then
                mPush $SD/$SDN
            else
                mPush $BUILDDIR
            fi
            sourceScript "${PRECONFIGCMDFILE}"
            res=$?
            mPop
            closeSecondaryLog
            return $res
            ;;
        config)
            setupSecondaryLog "config.log"
            log "GEN|INFO|Running config scripts" true
            mPush $BUILDDIR
            sourceScript "${CONFIGCMDFILE}"
            res=$?
            mPop
            closeSecondaryLog
            return $res
            ;;
        compile)
            setupSecondaryLog "compile.log"
            log "GEN|INFO|Running compile scripts" true
            mPush $BUILDDIR
            sourceScript "${COMPILECMDFILE}"
            res=$?
            mPop
            closeSecondaryLog
            return $res
            ;;
        check)
            setupSecondaryLog "check.log"
            log "GEN|INFO|Running check scripts" true
            mPush $BUILDDIR
            sourceScript "${CHECKCMDFILE}"
            res=$?
            mPop
            closeSecondaryLog
            return $res
            ;;
        preinstall)
            setupSecondaryLog "preinstall.log"
            log "GEN|INFO|Running PreInstall scripts" true
            mPush $BUILDDIR
            sourceScript "${PREINSTALLCMDFILE}"
            res=$?
            mPop
            closeSecondaryLog
            return $res
            ;;
        install)
            setupSecondaryLog "install.log"
            log "GENINFO|Running install scripts" true
            mPush $BUILDDIR
            sourceScript "${INSTALLCMDFILE}"
            res=$?
            mPop
            closeSecondaryLog
            [ $res -eq 0 ] && [ $NEXTPKG ] && log "GEN|INFO|Next package: \e[32m$NEXTPKG" t
            return $res
            ;;
        preimplement)
            setupSecondaryLog "preimplement.log"
            log "GEN|INFO|Running preImplement scripts" true
            mPush $BUILDDIR
            sourceScript "${PREIMPLEMENTCMDFILE}"
            res=$?
            closeSecondaryLog
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
            setupSecondaryLog "cleanup.log"
            cleanup
            closeSecondaryLog
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
        devmode)
            if [[ "$2" = "" ]]; then
                return
            fi
            DEVMODE=$2
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
        autobuild)
            runAutoBuildTmpToolChain
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
        [ $? -gt 0 ] && log "{GEN,ERR}|ERROR|EvalPrompt returned error on $command." t
        unset command
    done
}

## Checking user parameters
for arg in "$@"
do
    case "$arg" in
        --updatePkgFromLocal)
            updatePkgFromLocal
            [ $? -gt 0 ] && quitPkm 1 "Error happen, check your installation."
            quitPkm 0
            ;;
        --updatePkm)
            updatePkm
            [ $? -gt 0 ] && quitPkm 1 "Error happen, check your installation."
            quitPkm 0
            ;;
        --autoBuildTmpToolChain)
            singleton ## Ensure only one instance runs.
            [ $? -gt 0 ] && quitPkm 1 "Singleton check failed."
            log "NULL|INFO|Starting PKM" t
            readConfig
            startLog
            startupCheck
            runAutoBuildTmpToolChain
            [ $? -gt 0 ] && quitPkm 1 "AutoBuildTmpToolChain return error."
            quitPkm 0 "AutoBuildTmpToolChain succesful."
            ;;

    esac
done




singleton ## Ensure only one instance runs.
[ $? -gt 0 ] && quitPkm 1 "Singleton check failed."
log "NULL|INFO|Starting PKM" t
readConfig
startLog
startupCheck
prompt
