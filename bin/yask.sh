#!/bin/bash

##############################################################################
## YASK: Yet Another Stencil Kernel
## Copyright (c) 2014-2017, Intel Corporation
## 
## Permission is hereby granted, free of charge, to any person obtaining a copy
## of this software and associated documentation files (the "Software"), to
## deal in the Software without restriction, including without limitation the
## rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
## sell copies of the Software, and to permit persons to whom the Software is
## furnished to do so, subject to the following conditions:
## 
## * The above copyright notice and this permission notice shall be included in
##   all copies or substantial portions of the Software.
## 
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
## IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
## AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
## LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
## FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
## IN THE SOFTWARE.
##############################################################################

# Purpose: run stencil kernel in specified environment.
invo="Invocation: $0 $@"
echo $invo

# Env vars to set.
envs="OMP_DISPLAY_ENV=VERBOSE OMP_PLACES=cores"
envs="$envs KMP_VERSION=1 KMP_HOT_TEAMS_MODE=1 KMP_HOT_TEAMS_MAX_LEVEL=2"
envs="$envs I_MPI_PRINT_VERSION=1 I_MPI_DEBUG=5"

# Extra options for exe.
opts=""

unset arch                      # Don't want to inherit from env.
while true; do

    if [[ ! -n ${1+set} ]]; then
        break

    elif [[ "$1" == "-h" || "$1" == "-help" ]]; then
        opts="$opts -h"
        shift
        echo "$0 is a wrapper around the stencil executable to set up the proper environment."
        echo "usage: $0 -stencil <stencil> -arch <arch> [script-options] [--] [exe-options]"
        echo "required parameters to specify the executable:"
        echo "  -stencil <stencil>"
        echo "     Corresponds to stencil=<stencil> used during compilation"
        echo "  -arch <arch>"
        echo "     Corresponds to arch=<arch> used during compilation"
        echo "script-options:"
        echo "  -h"
        echo "     Print this help."
        echo "     To get executable help, run '$0 -stencil <stencil> -arch <arch> -- -help'"
        echo "  -host <hostname>|-mic <N>"
        echo "     Specify host to run executable on."
        echo "     'ssh <hostname>' will be pre-pended to the sh_prefix command."
        echo "     If -arch 'knl' is given, it implies the following (which can be overridden):"
        echo "       -exe_prefix 'numactl --preferred=1'"
        echo "     If -mic <N> is given, it implies the following (which can be overridden):"
        echo "       -arch 'knc'"
        echo "       -host "`hostname`"-mic<N>"
        echo "  -sh_prefix <command>"
        echo "     Add command-prefix before the sub-shell."
        echo "  -exe_prefix <command>"
        echo "     Add command-prefix before the executable."
        echo "  -ranks <N>"
        echo "     Simplified MPI run (x-dimension partition only)."
        echo "     'mpirun -n <N> -ppn <N>' is prepended to the exe_prefix command,"
        echo "     and '-nrx' <N> is passed to the executable."
        echo "     If a different MPI command or config is needed, use -exe_prefix <command>"
        echo "     explicitly and -nr* options as needed (and do not use '-ranks')."
        echo "  -log <file>"
        echo "     Write copy of output to <file>."
        echo "     Default is based on stencil, arch, host-name, and time-stamp."
        echo "     Use '/dev/null' to avoid making a log."
        echo "  <env-var=value>"
        echo "     Set environment variable <env-var> to <value>."
        echo "     Repeat as necessary to set multiple vars."
        echo " "
        exit 1

    elif [[ "$1" == "-stencil" && -n ${2+set} ]]; then
        stencil=$2
        shift
        shift

    elif [[ "$1" == "-arch" && -n ${2+set} ]]; then
        arch=$2
        shift
        shift

    elif [[ "$1" == "-sh_prefix" && -n ${2+set} ]]; then
        sh_prefix=$2
        shift
        shift

    elif [[ "$1" == "-exe_prefix" && -n ${2+set} ]]; then
        exe_prefix=$2
        shift
        shift

    elif [[ "$1" == "-log" && -n ${2+set} ]]; then
        logfile=$2
        shift
        shift

    elif [[ "$1" == "-host" && -n ${2+set} ]]; then
        host=$2
        shift
        shift

    elif [[ "$1" == "-mic" && -n ${2+set} ]]; then
        arch="knc"
        host=`hostname`-mic$2
        shift
        shift

    elif [[ "$1" == "-ranks" && -n ${2+set} ]]; then
        nranks=$2
        opts="$opts -nrx $nranks"
        shift
        shift

    elif [[ "$1" =~ ^[A-Za-z0-9_]+= ]]; then
        envs="$envs $1"
        shift

    elif [[ "$1" == "--" ]]; then
        shift
        
        # will pass remaining options to executable.
        break

    else
        # will pass remaining options to executable.
        break
    fi

done                            # parsing options.

# Check required opts.
if [[ -z ${stencil:+ok} ]]; then
    if [[ -z ${arch:+ok} ]]; then
        echo "error: missing required options: -stencil <stencil> -arch <arch>"
        exit 1
    fi
    echo "error: missing required option: -stencil <stencil>"
    exit 1
fi
if [[ -z ${arch:+ok} ]]; then
    echo "error: missing required option: -arch <arch>"
    exit 1
fi

# Set defaults for KNL.
# TODO: run numactl [on host] to determine if in flat mode.
if [[ "$arch" == "knl" ]]; then
    true ${exe_prefix='numactl --preferred=1'}
fi

# Simplified MPI in x-dim only.
if [[ -n "$nranks" ]]; then
    exe_prefix="mpirun -n $nranks -ppn $nranks $exe_prefix"
fi

# Bail on errors past this point.
set -e

# Actual host.
exe_host=${host:-`hostname`}

# Init log file.
true ${logfile=logs/yask.$stencil.$arch.$exe_host.`date +%Y-%m-%d_%H-%M-%S`.log}
echo "Writing log to '$logfile'."
mkdir -p `dirname $logfile`
echo $invo > $logfile

# These values must match the ones in Makefile.
tag=$stencil.$arch
exe="bin/yask.$tag.exe"
make_report=make-report.$tag.txt

# Try to build exe if needed.
if [[ ! -x $exe ]]; then
    echo "'$exe' not found or not executable; trying to build with default settings..."
    make clean; make -j stencil=$stencil arch=$arch 2>&1 | tee -a $logfile

# Or, save most recent make report to log if it exists.
elif [[ -e $make_report ]]; then
    echo "Build log from '$make_report':" >> $logfile
    cat $make_report >> $logfile
fi

# Double-check that exe exists.
if [[ ! -x $exe ]]; then
    echo "error: '$exe' not found or not executable." | tee -a $logfile
    exit 1
fi

# Additional setup for KNC.
if [[ $arch == "knc" && -n "$host" ]]; then
    dir=/tmp/$USER
    icc=`which icc`
    iccdir=`dirname $icc`/../..
    libpath=":$iccdir/compiler/lib/mic"
    ssh $host "rm -rf $dir; mkdir -p $dir/bin"
    scp $exe $host:$dir/bin
else
    dir=`pwd`
    libpath=":$HOME/lib"
fi

# Setup to run on specified host.
if [[ -n "$host" ]]; then
    sh_prefix="ssh $host $sh_prefix"
    envs="$envs PATH=$PATH LD_LIBRARY_PATH=./lib:$LD_LIBRARY_PATH$libpath"

    nm=1
    while true; do
        echo "Verifying access to '$host'..."
        ping -c 1 $host && ssh $host uname -a && break
        echo "Waiting $nm min before trying again..."
        sleep $(( nm++ * 60 ))
    done
else
    envs="$envs LD_LIBRARY_PATH=./lib:$LD_LIBRARY_PATH$libpath"
fi

# Command sequence.
cmds="cd $dir; uname -a; lscpu; numactl -H; ldd $exe; env $envs $exe_prefix $exe $opts $@"

date | tee -a $logfile
echo "===================" | tee -a $logfile

if [[ -z "$sh_prefix" ]]; then
    sh -c -x "$cmds" 2>&1 | tee -a $logfile
else
    echo "Running shell under '$sh_prefix'..."
    $sh_prefix "sh -c -x '$cmds'" 2>&1 | tee -a $logfile
fi

date | tee -a $logfile
echo "Log saved in '$logfile'."
