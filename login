#!/bin/bash
set -ex

TEMP=`getopt -o '' --long networks:,mounts: -n'login' -- "$@"`

if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

eval set -- "$TEMP"

NETWORKS=""
MOUNTS=""

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

dropbox start > /dev/null

is_vpac_accessible() {
    ip addr | grep -E '\<inet 172.31.[0-9]+.[0-9]+\>' > /dev/null
}

for MOUNT in $MOUNTS
do
    case $MOUNT in
    spud)
        if ! [ -f "/home/brian/zoph/.spud.txt" ]
        then
            sshfs root@dewey.microcomaustralia.com.au:/var/lib/zoph ~/zoph
        fi
    ;;

    home|vpac|archives)
        DIR="$HOME/private/$MOUNT"
        if ! [ -d "$DIR" ]
        then
            echo "Directory $DIR does not exist" >&2
            exit 1
        fi
        if ! mount | grep "^[a-z]\+ on $DIR type" > /dev/null
        then
            encfs --ondemand --extpass="ssh-askpass '$MOUNT mount'" --idle=60 "$HOME/encrypted/$MOUNT" "$DIR"
        fi
    ;;

    *)
        echo "Unknown mount $MOUNT" >&2
        exit 1
    ;;
    esac
done

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
            echo "openvpn failed to setup in time" >&2
            exit 1
        fi

        if ! ssh-add -l | grep d6:a6:03:0e:07:2d:96:3d:86:16:71:e1:76:f0:33:30 > /dev/null
        then
            if [ "`hostname`" = "aquitard" ]
            then
                ssh-add
            else
                ssh -t -A brian@sys12.in.vpac.org ssh-add
            fi
        fi
    ;;

    home)
        if ! ssh-add -l | grep 55:0c:bf:f1:d9:3d:d4:91:fe:b4:88:9d:c3:62:61:3d > /dev/null
        then
            if [ "`hostname`" = "webby" ] || [ "`hostname`" = "andean" ]
            then
                ssh-add
            else
                ssh -t -A brian@webby.microcomaustralia.com.au ssh-add
            fi
        fi
    ;;

    root)
        if ! ssh-add -l | grep 54:98:ba:eb:d8:dd:7f:1d:fe:7c:15:f3:66:7d:21:2c > /dev/null
        then
            if [ "`hostname`" = "webby" ] || [ "`hostname`" = "andean" ]
            then
                ssh-add
            else
                ssh -t -A brian@webby.microcomaustralia.com.au ssh-add .ssh/id_root
            fi
        fi
    ;;

    *)
        echo "Unknown network $NETWORK" >&2
        exit 1
    ;;
    esac
done

$HOME/tree/bin/backup --batch
