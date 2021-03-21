#!/bin/bash
#
# Copyright (C) 2004-2021, rncbc aka Rui Nuno Capela.
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
# /usr/sbin/rtirq
#
# Startup script for PREEMPT_RT / threadirqs enabled kernels.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License version 2 or later.
#
### BEGIN INIT INFO
# Provides:          rtirq
# Required-Start:    $syslog $local_fs $remote_fs
# Should-Start: $time alsa alsasound hotplug
# Required-Stop:     $syslog $local_fs $remote_fs
# Should-Stop: $time alsa alsasound hotplug
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Realtime IRQ thread tunning.
# Description:       Change the realtime scheduling policy
#	and priority of relevant system driver IRQ handlers.
### END INIT INFO
#
export LC_ALL=C

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
RTIRQ_CONFIG=/etc/rtirq.conf
[ -r ${RTIRQ_CONFIG} ] || RTIRQ_CONFIG=/etc/default/rtirq
[ -r ${RTIRQ_CONFIG} ] || {
	echo "`basename $0`: ${RTIRQ_CONFIG}: not found."
	[ "${RTIRQ_ACTION}" = "stop" ] && exit 0 || exit 6
}

# Read configuration.
source ${RTIRQ_CONFIG}


# Save/restore state file path (default).
RTIRQ_STATE=${RTIRQ_STATE:-/var/run/rtirq.state}

# Colon delimited trail list of already assigned IRQ numbers,
# preventind lower priority override due to shared IRQs.
RTIRQ_TRAIL=":"


#
# Get process-ids by thread handler names and IRQ number.
#
function rtirq_get_pids ()
{
	local NAME1=$1
	local NAME2=$2
	local IRQ=$3

	# Special for kernel-rt >= 2.6.31, where one can
	# prioritize shared IRQs by device driver (NAME2)...
	local PIDS=""
	# First try for IRQs re. PCI sound devices ("snd")...
	if [ "${NAME1}" == "snd" ]
	then
		PIDS=`ps -eo pid,comm | egrep -i "irq.${IRQ}.snd.${NAME2:0:4}" | awk '{print $1}'`
		if [ -z "${PIDS}" ]
		then
			PIDS=`ps -eo pid,comm | egrep -i "irq.${IRQ}.snd.*" | awk '{print $1}'`
		fi
	fi
	if [ -z "${PIDS}" ]
	then
		PIDS=`ps -eo pid,comm | egrep -i "irq.${IRQ}.${NAME2:0:8}" | awk '{print $1}'`
	fi
	# Backward compability for older kernel-rt < 2.6.31...
	if [ -z "${PIDS}" ]
	then
		PIDS=`ps -eo pid,comm | egrep -i "irq.${IRQ}" | awk '{print $1}'`
	fi
	echo ${PIDS}
}


#
# Check for services that are to be (un)threaded.
#
function rtirq_threaded ()
{
	local ACTION=$1
	local NAME1=$2
	local NAME2=$3
	local IRQ=$4

	if [ -n "`echo :${RTIRQ_NON_THREADED}: | sed 's/ /:/g' | grep :${NAME1}:`" ]
	then
		for THREADED in /proc/irq/${IRQ}/*/threaded
		do
			local PREPEND="Setting IRQ non-threaded: ${ACTION} [${NAME2}] irq=${IRQ}"
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
}


#
# IRQ thread handler policy prioritizer, by IRQ number.
#
function rtirq_start_irq ()
{
	local NAME1=$1
	local NAME2=$2
	local PRI2=$3
	local IRQ=$4

	# Check for services that are to be non-threaded.
	rtirq_threaded start "${NAME1}" "${NAME2}" ${IRQ}
	# And now do the proper threading prioritization...
	if [ -z "`echo ${RTIRQ_TRAIL} | grep :${NAME2}.${IRQ}:`" ]
	then
		# Find the IRQ tasklets...
		PIDS=`rtirq_get_pids ${NAME1} ${NAME2} ${IRQ}`
		# Whether a IRQ tasklet has been found.
		if [ -n "${PIDS}" ]
		then
			RTIRQ_TRAIL=":${NAME2}.${IRQ}${RTIRQ_TRAIL}"
		fi
		for PID in ${PIDS}
		do
			PREPEND="Setting IRQ priorities: start [${NAME2}] irq=${IRQ} pid=${PID}"
			# Save current state...
			local POL0=`${RTIRQ_CHRT} -p ${PID} | awk '/policy/ {print $NF}'`
			local PRI0=`${RTIRQ_CHRT} -p ${PID} | awk '/priority/ {print $NF}'`
			echo ${NAME1} ${NAME2} ${IRQ} ${PRI0} ${POL0} >> ${RTIRQ_STATE}
			# Start setting...
			local PREPEND="${PREPEND} prio=${PRI2}"
			if ${RTIRQ_CHRT} -p -f ${PRI2} ${PID}
			then
				echo "${PREPEND}: OK."
			else 
				echo "${PREPEND}: FAILED."
			fi
			PRI2=$((${PRI2} - 1))
			[ ${PRI2} -le ${PRI0_LOW} ] && PRI2=${PRI0_LOW}
		done
	fi
}


#
# IRQ thread handler policy prioritizer, by service name.
#
function rtirq_start_name ()
{
	local NAME1=$1
	local NAME2=$2
	local PRI1=$3

	local IRQS=`grep "${NAME2}" /proc/interrupts | awk -F: '{print $1}'`
	for IRQ in ${IRQS}
	do
		rtirq_start_irq "${NAME1}" "${NAME2}" ${PRI1} ${IRQ}
		PRI1=$((${PRI1} - 1))
		[ ${PRI1} -le ${PRI0_LOW} ] && PRI1=${PRI0_LOW}
	done
}


#
# Generic process top prioritizer
#
function rtirq_high ()
{
	local ACTION=$1

	local PRI1=0
	case ${ACTION} in
	*start)
		PRI1=99
		;;
	*)
		PRI1=50
		;;
	esac

	# Process all configured process names...
	for NAME in ${RTIRQ_HIGH_LIST}
	do
		local PREPEND="Setting IRQ high-priorities: ${ACTION} [${NAME}]"
		local PIDS=`ps -eo pid,comm | grep "${NAME}" | awk '{print $1}'`
		for PID in ${PIDS}
		do
			if ${RTIRQ_CHRT} -p -f ${PRI1} ${PID}
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
#  Start/save state.
#
function rtirq_start ()
{
	# Check configured base priority.
	local PRI0=${RTIRQ_PRIO_HIGH:-90}
	[ $((${PRI0})) -gt 95 ] && PRI0=95
	[ $((${PRI0})) -lt 55 ] && PRI0=55
	# Check configured priority decrease step.
	local DECR=${RTIRQ_PRIO_DECR:-5}
	[ $((${DECR})) -gt 10 ] && DECR=10
	[ $((${DECR})) -lt  1 ] && DECR=1
	# Check configured lower limit of priority.
	PRI0_LOW=${RTIRQ_PRIO_LOW:-51}
	[ $((${PRI0_LOW})) -gt $((${PRI0})) ] && PRI0_LOW=${PRI0}
	[ $((${PRI0_LOW})) -lt  51 ] && PRI0_LOW=51
	# (Re)set all softirq-timer/s to highest priority.
	rtirq_high start
	# Clear save/restore state.
	rm -f ${RTIRQ_STATE}
	# Process all configured service names...
	for NAME in ${RTIRQ_NAME_LIST}
	do
		case ${NAME} in
		snd)
			local PRI1=${PRI0}
			grep irq /proc/asound/cards | \
			sed 's/\(.*\) at.* irq \(.*\)/\2 \1/;s/with .*//' | \
			while read IRQ NAME1
			do
				grep "${NAME1}" /proc/asound/cards | \
				grep ]: | sed 's/.*]: \(.*\) - .*/\1/' | \
				while read NAME2
				do
					rtirq_start_irq "${NAME}" "${NAME2}" ${PRI1} ${IRQ}
					PRI1=$((${PRI1} - 1))
					[ ${PRI1} -le ${PRI0_LOW} ] && PRI1=${PRI0_LOW}
				done
			done
			;;
		usb)
			rtirq_start_name "${NAME}" "ohci.hcd" ${PRI0}
			rtirq_start_name "${NAME}" "uhci.hcd" ${PRI0}
			rtirq_start_name "${NAME}" "ehci.hcd" ${PRI0}
			rtirq_start_name "${NAME}" "xhci.hcd" ${PRI0}
			;;
		*)
			rtirq_start_name "${NAME}" "${NAME}" ${PRI0}
			;;
		esac
		[ ${PRI0} -gt ${DECR} ] && PRI0=$((${PRI0} - ${DECR}))
		[ ${PRI0} -le ${PRI0_LOW} ] && PRI0=${PRI0_LOW}
	done
}


#
#  Stop/restore state.
#
function rtirq_stop ()
{
	[ -f ${RTIRQ_STATE} ] && \
	while read NAME1 NAME2 IRQ PRI0 POLICY
	do
		local PIDS=`rtirq_get_pids "${NAME1}" "${NAME2}" ${IRQ}`
		for PID in ${PIDS}
		do
			local PREPEND="Setting IRQ priorities: stop [${NAME2}] irq=${IRQ} pid=${PID}"
			local OPTS=""
			case ${POLICY} in
			*SCHED_FIFO*)
				OPTS="${OPTS} -f"
				;;
			*SCHED_RR*)
				OPTS="${OPTS} -r"
				;;
			*SCHED_OTHER*)
				OPTS="${OPTS} -o"
				;;
			*SCHED_BATCH*)
				OPTS="${OPTS} -b"
				;;
			*SCHED_IDLE*)
				OPTS="${OPTS} -i"
				;;
			*SCHED_RESET_ON_FORK*)
				OPTS="${OPTS} -R"
				;;
			esac
			if ${RTIRQ_CHRT} ${OPTS} -p ${PRI0} ${PID}
			then
				echo "${PREPEND} pid=${PID} prio=${PRI0}: OK."
			else 
				echo "${PREPEND} pid=${PID} prio=${PRI0}: FAILED."
			fi

		done
		rtirq_threaded stop "${NAME1}" "${NAME2}" ${IRQ}
	done < ${RTIRQ_STATE}
	# Clear save/restore state.
	rm -f ${RTIRQ_STATE}
	# Stop all softirq-timer/s from highest priority.
	rtirq_high stop
}


# 
# Reset policy of all IRQ threads out there. 
#
function rtirq_reset ()
{
	PIDS=`ps -eo pid,comm | egrep -i "irq.[0-9]+" | awk '{print $1}'`
	for PID in ${PIDS}
	do
		${RTIRQ_CHRT} -p -f 50 ${PID}
	done
	# Reset all softirq-timer/s from highest priority.
	rtirq_high reset
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
	rtirq_start
	;;
stop)
	rtirq_stop
	if [ "${RTIRQ_RESET_ALL}" = "yes" -o "${RTIRQ_RESET_ALL}" = "1" ]
	then
		rtirq_reset
	fi
	;;
reset)
	rtirq_reset
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
