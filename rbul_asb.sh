#!/bin/sh -x

#vnet

SLEEP=/usr/bin/sleep    ## FOR OPENWRT
#SLEEP=/bin/sleep       ## FOR LINUX

[ -f /usr/bin/sleep  ] || (echo 'Install "coreutils-sleep" package on OpenWRT. In Linux built-in /bin/sleep is OK' && exit 1)

FPING=/usr/bin/fping4   ## FOR OPENWRT
#FPING=/usr/bin/fping   ## FOR LINUX

[ -f /usr/bin/fping ] || (echo 'Install "fping" package' && exit 1)

PROGRAM_NAME=`basename $(echo $0)`
grep $PROGRAM_NAME /etc/iproute2/rt_protos | grep -v ^# || echo "50      $PROGRAM_NAME" >> /etc/iproute2/rt_protos

## Create state file
STATE_FILE="/tmp/$PROGRAM_NAME"
echo -e "STATE FILE\n================" > $STATE_FILE

routes () {

        ACTION=$1
        ID=$2

        case $ID in
            1)
                ip route $ACTION 0.0.0.0/1     via 10.150.1.21 dev alma-srv-3 src 10.150.1.22 metric $ID protocol $PROGRAM_NAME > /dev/null 2>&1  
                ip route $ACTION 128.0.0.0/1   via 10.150.1.21 dev alma-srv-3 src 10.150.1.22 metric $ID protocol $PROGRAM_NAME > /dev/null 2>&1  
                ;;
            2)
                ip route $ACTION 0.0.0.0/1     via 10.150.0.201 dev alma-gw-0 src 10.150.0.202 metric $ID protocol $PROGRAM_NAME > /dev/null 2>&1     
                ip route $ACTION 128.0.0.0/1   via 10.150.0.201 dev alma-gw-0 src 10.150.0.202 metric $ID protocol $PROGRAM_NAME > /dev/null 2>&1 
                ;;
            3)
                ip route $ACTION 0.0.0.0/1     via 192.168.0.3 dev eth1       src 192.168.0.21 metric $ID protocol $PROGRAM_NAME > /dev/null 2>&1     
                ip route $ACTION 128.0.0.0/1   via 192.168.0.3 dev eth1       src 192.168.0.21 metric $ID protocol $PROGRAM_NAME > /dev/null 2>&1 
                ;;
            4) 
                ip route $ACTION 0.0.0.0/1     via 10.150.1.21 dev alma-srv-3 src 10.150.1.22 metric $ID protocol $PROGRAM_NAME > /dev/null 2>&1     
                ip route $ACTION 128.0.0.0/1   via 10.150.1.21 dev alma-srv-3 src 10.150.1.22 metric $ID protocol $PROGRAM_NAME > /dev/null 2>&1 
                ;;
        esac

}

pinger () {

        ## $1 - order number (ID) $2 - address to ping
        ID=$1
        HOST_TO_PING=$2
        PING_INTERVAL_MS=190    ## waiting for a reply in milliseconds (should be less than PING_INTERVAL_S?)
        PING_INTERVAL_S=1       ## interval between ping sendings in seconds
        MAX_FAIL_COUNT=10       ## Maximum number of failure pings to remove route
        MAX_SUCCESS_COUNT=10    ## Maximum number of successive pings to add route back

        FAIL_COUNT=0            ## Initializing
        SUCCESS_COUNT=0         ## Initiatizing
        LINK_STATE=INIT         ## Initializing
#        CURRENT_ROUTE=INIT      ## Initializing

#        ## State file write
#        echo 'CURRENT_ROUTE=INIT' > $STATE_FILE

        while true
                do
                       fping -q -u -b 12 -c 1 -r 1 -t $PING_INTERVAL_MS $HOST_TO_PING  > /dev/null 2>&1
                        RETURN_CODE=$?
                        if [ $RETURN_CODE -eq 0 ] 
                                then SUCCESS_COUNT=$(( $SUCCESS_COUNT + 1))
                                FAIL_COUNT=0

                                 if [ $SUCCESS_COUNT -eq $MAX_SUCCESS_COUNT ]
                                         then
                                                 PING_INTERVAL_S=1 ## Expand interval when everything is OK to decrease CPU load

                                                 if [ $LINK_STATE != UP ] 
                                                     then 
                                                         routes replace $ID
                                                         logger -s -t $PROGRAM_NAME "Link $ID is up: Host $HOST_TO_PING is reachable"
                                                         grep -q "^LINK_STATE_$ID=" $STATE_FILE && sed "s/^LINK_STATE_$ID=.*/LINK_STATE_$ID=UP/" -i $STATE_FILE || sed "$ a\LINK_STATE_$ID=UP" -i $STATE_FILE
                                                         CURRENT_ROUTE=$(for ID in `seq 1 4`; do sed -n "/^LINK_STATE_$ID=UP/p" $STATE_FILE ; done | head -n 1 | cut -d '=' -f 1 | cut -d '_' -f 3)
                                                         grep -q "^CURRENT_ROUTE=" $STATE_FILE && sed "s/^CURRENT_ROUTE=.*/CURRENT_ROUTE=$CURRENT_ROUTE/" -i $STATE_FILE || sed "/============/a CURRENT_ROUTE=$CURRENT_ROUTE" -i $STATE_FILE

                                                 fi

                                                LINK_STATE=UP ## Trigger current route state
                                 fi
                        fi 

                        if [ $RETURN_CODE -ne 0 ]
                            then FAIL_COUNT=$(( $FAIL_COUNT + 1 ))
                            SUCCESS_COUNT=0
                            PING_INTERVAL_S=0.1 ## Shrink interval when ping is lost

                            if [ $FAIL_COUNT -eq $MAX_FAIL_COUNT ] 
                                then 

                                    if [ $LINK_STATE != DOWN ]
                                        then
                                            routes delete $ID
                                            logger -s -t $PROGRAM_NAME "Link $ID is down: Host $HOST_TO_PING is unreachable"
                                            grep -q "^LINK_STATE_$ID=" $STATE_FILE && sed "s/^LINK_STATE_$ID=.*/LINK_STATE_$ID=DOWN/" -i $STATE_FILE || sed "$ a\LINK_STATE_$ID=DOWN" -i $STATE_FILE
                                            CURRENT_ROUTE=$(for ID in `seq 1 4`; do sed -n "/^LINK_STATE_$ID=UP/p" $STATE_FILE ; done | head -n 1 | cut -d '=' -f 1 | cut -d '_' -f 3)
                                            grep -q "^CURRENT_ROUTE=" $STATE_FILE && sed "s/^CURRENT_ROUTE=.*/CURRENT_ROUTE=$CURRENT_ROUTE/" -i $STATE_FILE || sed "/============/a CURRENT_ROUTE=$CURRENT_ROUTE" -i $STATE_FILE

                                    fi

                                    LINK_STATE=DOWN ## Trigger current route state
                            fi

                        fi

                        $SLEEP $PING_INTERVAL_S
                done

}

case  $1 in
        start)
             routes replace 1
             routes replace 2
#             routes replace 3
#             routes replace 4
            pinger 1 10.150.0.41  &
            pinger 2 10.150.0.201 &
#            pinger 3 10.240.0.3 &
#            pinger 4 10.240.0.4 &
        ;;
        stop)
             routes delete 1
             routes delete 2                                                                                             
#             routes delete 3                                                                                            
#             routes delete 4
             rm $STATE_FILE
            killall $PROGRAM_NAME
        ;;
        *)
           echo "Usage: $0 start|stop"
esac
