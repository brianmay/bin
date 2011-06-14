#!/bin/bash
# -*- Mode: shell-script -*-
#template by ~tconnors/bin/newshscript
#Sun Nov 26 20:59:02 EST 2006
# $Revision: 1.6 $ $Date: 2007/02/10 06:58:25 $
# $Id: fsh,v 1.6 2007/02/10 06:58:25 tconnors Exp $
# $Header: /home/ssi/tconnors/cvsroot/bin/fsh,v 1.6 2007/02/10 06:58:25 tconnors Exp $
# $RCSfile: fsh,v $

# This program does fsh using ssh native master sockets


usageerror () {
    if [ "$#" != 0 ] ; then
        echo "Usage error: $@" 1>&2
    fi
    exit 1
}

export POSIXLY_CORRECT=yes
TEMP=`getopt -o 'tCTfnvVXxl:o:' -n'fsh' -- "$@"`

if [ $? != 0 ] ; then usageerror "wrong parameters" >&2 ; exit 1 ; fi

eval set -- "$TEMP"

OPERATION=""

declare -a flags
flags=
host=
while true
do
    i=0
    case "$1" in
        -t|-C|-T|-f|-n|-v|-V|-X|-x) #flags that don't take an argument
            flags[i]=$1
            i=$(($i+1))
            shift;
            ;;
        -l|-o)   #flags take an argument
            flags[i]="$1";
            i=$(($i+1))
            shift;

            flags[i]="$1";
            i=$(($i+1))
            shift;
            ;;
        --)
            shift
            break
            ;;
        *) echo "Internal error parsing $1!" ; exit 1 ;;
    esac
done

if [ "$#" -lt 1 ] ; then
    usageerror "supply host"
fi
host="$1"
shift

#assign all uneaten params to an array
i=0
declare -a args
for arg in "$@" ; do
    args[i]=$arg
    i=$(($i+1))
done

sockfile="$TMP/ssh.%r@%h:%p.sock"

if ! ssh -O check -o ControlPath=$sockfile "${flags[@]}" "$host" 2>&1 | grep -q 'Master running' ; then
    ssh -f -o ControlMaster=yes -o "ControlPath=$sockfile" -N "${flags[@]}" "$host" < /dev/null >& /dev/null
fi


ssh -o ControlMaster=no -o "ControlPath=$sockfile" "${flags[@]}" "$host" "${args[@]}"

