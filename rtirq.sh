#!/bin/bash
#
# Copyright (c) 2004-2011 rncbc aka Rui Nuno Capela.
#
#   This program is free software; you can redistribute it and/or
#   modify it under the terms of the GNU General Public License
#   as published by the Free Software Foundation; either version 2
#   of the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License along
#   with this program; if not, write to the Free Software Foundation, Inc.,
#   51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# /etc/init.d/rtirq
#
# Startup script for realtime-preempt enabled kernels.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License version 2 or later.
#
# chkconfig: 35 81 19
# description: Realtime IRQ thread tunning.
#
### BEGIN INIT INFO
# Provides:          rtirq
# Required-Start:    $syslog $local_fs
# Should-Start: $time alsa alsasound hotplug
# Required-Stop:     $syslog $local_fs
# Should-Stop: $time alsa alsasound hotplug
# Default-Start:     3 5
# Default-Stop:      0 1 2 6
# Short-Description: Realtime IRQ thread tunning.
# Description:       Change the realtime scheduling policy
#	and priority of relevant system driver IRQ handlers.
### END INIT INFO
#


# Won't work without those binaries.
for DIR in /sbin /usr/sbin /bin /usr/bin /usr/local/bin; do
	[ -z "${RTIRQ_CHRT}" -a -x ${DIR}/chrt ] && RTIRQ_CHRT=${DIR}/chrt
done

# Check for missing binaries (stale symlinks should not happen)
[ -n "${RTIRQ_CHRT}" -a -x ${RTIRQ_CHRT} ] || {
	echo "`basename $0`: chrt: not installed."  
	[ "$1" = "stop" ] && exit 0 || exit 5
}

# Check for existence of needed config file and read it.
RTIRQ_CONFIG=/etc/sysconfig/rtirq
[ -r ${RTIRQ_CONFIG} ] || RTIRQ_CONFIG=/etc/default/rtirq
[ -r ${RTIRQ_CONFIG} ] || RTIRQ_CONFIG=/etc/rtirq.conf
[ -r ${RTIRQ_CONFIG} ] || {
	echo "`basename $0`: ${RTIRQ_CONFIG}: not found."
	[ "${RTIRQ_ACTION}" = "stop" ] && exit 0 || exit 6
}

# Read configuration.
source ${RTIRQ_CONFIG}

# Colon delimited trail list of already assigned IRQ numbers,
# preventind lower priority override due to shared IRQs.
RTIRQ_TRAIL=":"

# 
# Reset policy of all IRQ threads out there. 
#
function rtirq_reset ()
{
	# Reset all softirq-timer/s from highest priority.
	rtirq_exec_high reset
	# PIDS=`ps -eo pid,class | egrep '(FF|RR)' | awk '{print $1}'`
	PIDS=`ps -eo pid,comm | grep -i IRQ | awk '{print $1}'`
	for PID in ${PIDS}
	do
		${RTIRQ_CHRT} --pid --other 0 ${PID}
	done
}

#
# IRQ thread handler policy prioritizer, by IRQ number.
#
function rtirq_exec_num ()
{
	ACTION=$1
	NAME1=$2
	NAME2=$3
	PRI2=$4
	IRQ=$5
	# Check the services that are to be (un)threaded.
	if [ -n "`echo :${RTIRQ_NON_THREADED}: | sed 's/ /:/g' | grep :${NAME1}:`" ]
	then
		PREPEND="Setting IRQ priorities: ${ACTION} [${NAME2}] irq=${IRQ}"
		for THREADED in /proc/irq/${IRQ}/*/threaded
		do
			if [ -f "${THREADED}" ]
			then
				case ${ACTION} in
				*start)
					echo "${PREPEND}: ${THREADED}: OFF."
					echo -n 0 > "${THREADED}"
					;;
				stop)
					echo "${PREPEND}: ${THREADED}: ON."
					echo -n 1 > "${THREADED}"
					;;
				esac
			fi
		done
	fi
	# And now do the proper threading prioritization...
	if [ -z "`echo ${RTIRQ_TRAIL} | grep :${IRQ}:`" ]
	then
		# Special for kernel-rt >= 2.6.31, where one can
		# prioritize shared IRQs by device driver (NAME2)...
		PIDS=`ps -eo pid,comm | egrep -i "IRQ.${IRQ}.${NAME2:0:8}" | awk '{print $1}'`
		if [ -n "${PIDS}" ]
		then
			RTIRQ_TRAIL=":${IRQ}${RTIRQ_TRAIL}"
		else
			# Backward compability for older kernel-rt < 2.6.31...
			PIDS=`ps -eo pid,comm | egrep -i "IRQ.${IRQ}" | awk '{print $1}'`
			if [ -n "${PIDS}" ]
			then
				RTIRQ_TRAIL=":${IRQ}${RTIRQ_TRAIL}"
			fi
		fi
		for PID in ${PIDS}
		do
			PREPEND="Setting IRQ priorities: ${ACTION} [${NAME2}] irq=${IRQ} pid=${PID}"
			case ${ACTION} in
			*start)
				PREPEND="${PREPEND} prio=${PRI2}"
				if ${RTIRQ_CHRT} --pid --fifo ${PRI2} ${PID}
				then
					echo "${PREPEND}: OK."
				else 
					echo "${PREPEND}: FAILED."
				fi
				;;
			stop)
				if ${RTIRQ_CHRT} --pid --other 0 ${PID}
				then
					echo "${PREPEND}: OK."
				else 
					echo "${PREPEND}: FAILED."
				fi
				;;
			status)
				echo "${PREPEND}: " && ${RTIRQ_CHRT} --pid --verbose ${PID}
				;;
			*)
				echo "${PREPEND}: ERROR."
				;;
			esac
			PRI2=$((${PRI2} - 1))
		done
	fi
}

#
# IRQ thread handler policy prioritizer, by service name.
#
function rtirq_exec_name ()
{
	ACTION=$1
	NAME1=$2
	NAME2=$3
	PRI1=$4
	IRQS=`grep "${NAME2}" /proc/interrupts | awk -F: '{print $1}'`
	for IRQ in ${IRQS}
	do
		rtirq_exec_num ${ACTION} "${NAME1}" "${NAME2}" ${PRI1} ${IRQ}
		PRI1=$((${PRI1} - 1))
	done
}

#
# Generic process top prioritizer
#
function rtirq_exec_high ()
{
	ACTION=$1
	case ${ACTION} in
	*start)
		PRI1=99
		;;
	*)
		PRI1=1
		;;
	esac
	# Process all configured process names...
	for NAME in ${RTIRQ_HIGH_LIST}
	do
		PREPEND="`basename $0`: ${ACTION} [${NAME}]"
		PIDS=`ps -eo pid,comm | grep "${NAME}" | awk '{print $1}'`
		for PID in ${PIDS}
		do
			if ${RTIRQ_CHRT} --pid --fifo ${PRI1} ${PID}
			then
				echo "${PREPEND} pid=${PID} prio=${PRI1}: OK."
			else 
				echo "${PREPEND} pid=${PID} prio=${PRI1}: FAILED."
			fi
		done
		[ ${PRI1} -gt ${RTIRQ_PRIO_HIGH} ] && PRI1=$((${PRI1} - 1))
	done
}


#
# Main executive.
#
function rtirq_exec ()
{
	ACTION=$1
	# Check configured base priority.
	PRI0=${RTIRQ_PRIO_HIGH:-90}
	[ $((${PRI0})) -gt 95 ] && PRI0=95
	[ $((${PRI0})) -lt 55 ] && PRI0=55
	# Check configured priority decrease step.
	DECR=${RTIRQ_PRIO_DECR:-5}
	[ $((${DECR})) -gt 10 ] && DECR=10
	[ $((${DECR})) -lt  1 ] && DECR=1
	# (Re)set all softirq-timer/s to highest priority.
	rtirq_exec_high ${ACTION}
	# Process all configured service names...
	for NAME in ${RTIRQ_NAME_LIST}
	do
		case ${NAME} in
		snd)
			PRI1=${PRI0}
			grep irq /proc/asound/cards | tac | \
			sed 's/\(.*\) at .* irq \(.*\)/\2 \1/' | \
			while read IRQ NAME1
			do
				grep "${NAME1}" /proc/asound/cards | \
				sed 's/\(.*\)]: \(.*\) - \(.*\)/\2/' | \
				while read NAME2
				do
					rtirq_exec_num ${ACTION} "${NAME}" "${NAME2}" ${PRI1} ${IRQ}
					PRI1=$((${PRI1} - 1))
				done
			done
			;;
		usb)
			rtirq_exec_name ${ACTION} "${NAME}" "ohci_hcd" ${PRI0}
			rtirq_exec_name ${ACTION} "${NAME}" "uhci_hcd" ${PRI0}
			rtirq_exec_name ${ACTION} "${NAME}" "ehci_hcd" ${PRI0}
			;;
		*)
			rtirq_exec_name ${ACTION} "${NAME}" "${NAME}" ${PRI0}
			;;
		esac
		[ ${PRI0} -gt ${DECR} ] && PRI0=$((${PRI0} - ${DECR}))
	done
}


#
# Main procedure line.
#
case $1 in
start)
	if [ "${RTIRQ_RESET_ALL}" = "yes" -o "${RTIRQ_RESET_ALL}" = "1" ]
	then
		rtirq_reset
	fi
	rtirq_exec start
	;;
stop)
	if [ "${RTIRQ_RESET_ALL}" = "yes" -o "${RTIRQ_RESET_ALL}" = "1" ]
	then
		rtirq_reset
	#else
	#  rtirq_exec stop
	fi
	;;
reset)
	if [ "${RTIRQ_RESET_ALL}" = "yes" -o "${RTIRQ_RESET_ALL}" = "1" ]
	then
		rtirq_reset
	else
		rtirq_exec stop
	fi
	;;
restart|force-reload)
	$0 stop || true
	$0 start
	;;
status)
	echo
	#rtirq_exec status
	ps -eo pid,class,rtprio,ni,pri,pcpu,stat,comm --sort -rtprio \
		| egrep '(^[ |\t]*PID|IRQ|softirq|sirq|irq\/)' \
		| awk 'BEGIN {
			while (getline IRQLine < "/proc/interrupts") {
				split(IRQLine, IRQSplit, ":[ |\t|0-9]+");
				if (match(IRQSplit[1], "^[ |\t]*[0-9]+$")) {
					gsub("[^ |\t]+(PIC|MSI)[^ |\t]*[ |\t]+" \
						"|\\[[^\\]]+\\][^ |\t]*[ |\t]+",
						"", IRQSplit[2]);
					IRQTable[IRQSplit[1] + 0] = IRQSplit[2];
				}
			}
		} { if ($9 == "")
			{ print $0"\t"IRQTable[substr($8,5)]; }
			else
			{ print $0"\t"IRQTable[$9]; } }'
	echo
	;;
*)
	echo
	echo "  Usage: $0 {[re]start|stop|reset|status|force-reload}"
	echo
	exit 1
	;;
esac

exit 0
