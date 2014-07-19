#!/bin/bash
set -ex

TEMP=`getopt -o '' --long networks:,mounts: -n'login' -- "$@"`

if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

eval set -- "$TEMP"

NETWORKS=""
MOUNTS=""
do_home=""

while true
do
	case "$1" in
	--networks)
		shift
		NETWORKS="$1"
		shift;
		;;
	--mounts)
		shift
		MOUNTS="$1"
		shift;
		;;
	--)
		shift;
		break ;;
	*) echo "Internal error!" ; exit 1 ;;
	esac
done

is_vpac_accessible() {
    ip addr | grep -E '\<inet 172.31.[0-9]+.[0-9]+\>' > /dev/null
}

is_home_accessible() {
    return 0
    if nc merlock.pri ssh < /dev/null > /dev/null
    then
        return 0
    else
        return 1
    fi
}


for NETWORK in $NETWORKS
do
    case "$NETWORK" in
    vpac)
        if ! is_vpac_accessible
        then
            cd "$HOME/tree/lib/openvpn"
            if ! sudo openvpn --config vpac.conf --daemon
            then
                echo "openvpn failed" >&2
                exit 1
            fi

            for i in {1..10}
            do
                sleep 1
                if is_vpac_accessible
                then
                    break
                fi
            done
        fi

        if ! is_vpac_accessible
        then
            echo "vpac failed to setup in time" >&2
            exit 1
        fi

        if ! ssh-add -l | grep d6:a6:03:0e:07:2d:96:3d:86:16:71:e1:76:f0:33:30 > /dev/null
        then
            PREFIX=""
            if [ "`hostname`" != "aquitard" ]
            then
                PREFIX="ssh -t -A brian@sys12.in.vpac.org"
            fi
            $PREFIX ssh-add /home/brian/.ssh/id_rsa
        fi
    ;;

    home)
        if ! ssh-add -l | grep 55:0c:bf:f1:d9:3d:d4:91:fe:b4:88:9d:c3:62:61:3d > /dev/null
        then
            PREFIX=""
            if [ "`hostname`" != "webby" ] && [ "`hostname`" != "andean" ]
            then
                PREFIX="ssh -t -A brian@webby.microcomaustralia.com.au"
#                PREFIX="ssh -t -A brian@webby.pri"
            fi
            $PREFIX ssh-add "/home/brian/.ssh/id_rsa"
        fi

        if ! is_home_accessible
        then
            xterm -e sudo SSH_AUTH_SOCK="$SSH_AUTH_SOCK" ~/tree/bin/sshuttle_home --ipv6 --tproxy &

            for i in {1..10}
            do
                sleep 1
                if is_home_accessible
                then
                    break
                fi
            done
        fi

        if ! is_home_accessible
        then
            echo "home failed to setup in time" >&2
            exit 1
        fi

        do_home="yes"
        # git annex assistant --autostart
        $HOME/tree/bin/backup --batch
    ;;

    root)
        if ! ssh-add -l | grep 54:98:ba:eb:d8:dd:7f:1d:fe:7c:15:f3:66:7d:21:2c > /dev/null
        then
            PREFIX=""
            if [ "`hostname`" != "webby" ] && [ "`hostname`" != "andean" ]
            then
                PREFIX="ssh -t -A brian@webby.microcomaustralia.com.au"
            fi
            $PREFIX ssh-add "/home/brian/.ssh/id_root"
        fi
    ;;

    *)
        echo "Unknown network $NETWORK" >&2
        exit 1
    ;;
    esac
done

for MOUNT in $MOUNTS
do
    case $MOUNT in
    spud)
        if ! [ -f "/home/brian/spud/.spud.txt" ]
        then
            sshfs root@dewey.microcomaustralia.com.au:/var/lib/spud ~/spud
        fi
    ;;

    home|vpac|backdoors|archives)
        if [ -n "$do_home" ]
        then
            DIR="/mnt/brian/private/$MOUNT"
            if ! [ -d "$DIR" ]
            then
                mkdir -p "$DIR"
            fi
            if ! mount | grep "^[a-z]\+ on $DIR type" > /dev/null
            then
                encfs "$HOME/encrypted/$MOUNT" "$DIR"
            fi
        else
            echo "Skipping mount of $MOUNT" >&2
        fi
    ;;

    *)
        echo "Unknown mount $MOUNT" >&2
        exit 1
    ;;
    esac
done
