#!/bin/bash

###
# Better variable naming.
###
declare sd="/sources"
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

###
# There is too many log files. Implement debug level to reduce.
# Log files
# 0 = Default; 1 = Unpacking; 2 = Preconfig; 3 = Config; 4 = Compile; 5 = Check;
# 6 = PreInstall; 7 = Install; 8 = PreImplement; 9 = Implement; 10 = PostImplement
###
declare -a lf=() # Will contain a list of all log files.
declare FAKEROOT="/usr/Fakeroot"
declare CURSTATE=0 # Set to 1 to exit program succesfully
declare confBase="/etc/pkm"

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
            eval $c | tee -a 2>> $ld/$lf[0]
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

function loadCommands {
    log "ERROR: Call to loadCommands should not exists." true
    return
    log "INFO: Loading commands into variables." true
    IFS=$'\n'
    declare tmpLine
    declare useTmp
    while read line; do
        preconfigCmd+=($line)
    done < $preconfigCmdFile
    while read line; do
        configCmd+=($line)
    done < $configCmdFile
    while read line; do
        compileCmd+=($line)
    done < $compileCmdFile
    while read line; do
        checkCmd+=($line)
    done < $checkCmdFile

    while read line; do
        preInstallCmd+=($line)
    done < $preInstallCmdFile
    while read line; do
        installCmd+=($line)
    done < $installCmdFile
    while read line; do
        preImplementCmd+=($line)
    done < $preImplementCmdFile
    while read line; do
        postImplementCmd+=($line)
    done < $postImplementCmdFile
    unset IFS
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
        if [[ $lf == "" ]]; then
            echo -e "NOLOG-"$MSG
            return
        fi
        echo $M |tee -a $ld/${lf[0]}
        return
    fi
    if [[ $lf == "" ]]; then
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

function sourceScript {
    c=$1
    log "INFO: Sourcing: $c" true
    source $c
    res=$?
    log "INFO: Sourced $c returned: $res" true
    if [[ $res > 0 ]]; then
        evalError $c
    fi
}

function implementPkg {
    pushd $FAKEROOT/$sdn > /dev/null
    if [[ $? > 0 ]]; then
        log "FATAL: pushd to $FAKEROOT/$sdn failed." true
        exit 1
    fi

    log "INFO: Setting file in system" true
    log "file:$ld/${lf[9]}"
    tar cvf - . | (cd / ; tar vxf - ) |tee -a $ld/${lf[9]} 2>> $ld/$lf
    popd > /dev/null 2>&1
}

function cleanup {
    log "INFO: Cleaning up source file" true
    pushd $sd > /dev/null
    if [[ $? > 0 ]]; then
        log "FATAL: pushd to $sd failed." true
        exit 1
    fi

    rm -vfr $sdn | tee -a $ld/$lf 2>> $ld/$lf
    popd > /dev/null 2>&1

    promptUser "Remove Fakeroot Files? y/N"
    read x
    case $x in
        [yY])
            log "INFO: Removing fakeroot." true
            rmFR="rm -vfr $FAKEROOT/$sdn"
            log "INFO: Running Cmd: $rmFR" true
            eval $rmFr
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
    if [[ ! "$pkg" == "" ]]; then
        echo "Unloading previous package from memory."
        unloadPkg
    fi

    promptUser "Package name?"
    read -e pkg

    # If we can't file the package (source tar), we do a search for the term provided by the user.
    if [ ! -f $sd/$pkg ]; then
        log "ERROR: Package not found in $sd." true
        log "INFO: Searching for $pkg*." true
        declare -a foundFiles
        for file in `find $sd/ -maxdepth 1 -type f -iname $pkg*.*`; do
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
    log "INFO: Checking log directorie: $ld" true
    if [ ! -d "$ld" ]; then
        log "INFO: Creating log directory" true
        md="mkdir -vp $ld"
        eval $md
        if [[ $? > 0 ]]; then
            log "FATAL: Error creating log directory" true
            exit 1
        fi
    fi

    setLF

    if [ -d $sdnConf ]; then
        log "WARNING: Config Directory exists. Previous configuration file will be left intact." true
    else
        md="mkdir -vp $sdnConf/"
        log "INFO: Creating package configuration directory: $md" true
        eval $md | tee -a $ld/${lf[0]} 2>> $ld/$lf[0]
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
    eval $ct | tee -a $ld/${lf[0]} 2>> $ld/$lf[0]
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
        eval $tc | tee -a $ld/${lf[0]} 2>> $ld/$lf[0]
        if [[ $? > 0 ]]; then
            evalError $tc
            return
        fi
        log "INFO: Add configuration headers to $fn" true
        cat $confBase/configHeaders > $fn
        ((i++))
    done

    log "INFO: Configuration created." true

}

function unloadPkg {
    unset -v pkg sdnConf tf sdn hasBuildDir banner genConfigFile preconfigCmdFile configCmdFile compileCmdFile checkCmdFile preInstallCmdFile installCmdFile preImplementCmdFile postImplementCmdFile cmdFileList preconfigCmd configCmd compileCmd checkCmd preInstallCmd installCmd preImplementCmd postImplementCmd
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
        for file in `find $confBase -type d -iname $pkg*.*`; do
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
            *) echo "Unknow params";;
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
    printf "sd: $sd
tf: $tf
sdnConf: $sdnconf
ext: $ext
hasBuildDir: $hasBuildDir
MAKEFLAGS: $MAKEFLAGS
buildDir: $buildDir\n"
}

function evalError {
    log "ERROR: Error during eval: $1" true
}

function prompt {
    while [[ $CURSTATE == [0] ]]; do
        echo -e $banner
        promptUser "Input."
        read -e command
        case $command in
            list\ commands)
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
                sourceScript "$preConfigCmdFile"
                log "INFO: Running pre-config scripts" true
                log "file:$ld/${lf[2]}"
                popd > /dev/null 2>&1
                ;;
            config)
                log "INFO: Running config scripts" true
                log "file:$ld/${lf[3]}"
                pushd $buildDir > /dev/null
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
                sourceScript "compile"
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
                sourceScript "check"
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
                sourceScript "preInstall"
                popd > /dev/null 2>&1
                ;;
            install)
                log "INFO: Running install scripts" true
                log "INFO: FakeRoot: $FAKEROOT/$sdn" tru
                log "file:$ld/${lf[7]}"
                pushd $buildDir > /dev/null
                if [[ $? > 0 ]]; then
                    log "FATAL: pushd to $buildDir failed." true
                    exit 1
                fi
                sourceScript "install"
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
                sourceScript "preImplement"
                popd > /dev/null 2>&1
                ;;
            implement)
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
                sourceScript "postImplement"
                popd > /dev/null 2>&1
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
            dump\ env)
                dumpEnv
                ;;
            quit)
                echo "Quitting"
                CURSTATE=1
                ;;
            *)
                echo "Unknown command"
                ;;
        esac

    done
}

export MAKEFLAGS

prompt
