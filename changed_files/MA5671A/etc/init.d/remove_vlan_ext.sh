#!/bin/sh /etc/rc.common

START=110

start() {
	while true
	do
		result=`/opt/lantiq/bin/omci_pipe.sh managed_entity_get 171 257 | grep errorcode | head -1`
		status=${result%% *}
		if [ "$status" == "errorcode=0" ]; then
			/opt/lantiq/bin/omci_pipe.sh managed_entity_delete 171 257
			logger -s -p daemon.err -t "[vlanTableRemoved]" 2> /dev/console
		fi
		sleep 30
 	done &
}