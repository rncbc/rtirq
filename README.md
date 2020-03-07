# rtirq
rtirq - Startup script for realtime-preempt enabled kernels

Your package manager may make this package availabe as `rtirq-init`.

This script allows to make use of the threaded IRQs as used by real-time kernels or kernels >= 2.6.39 with the threadirqs kernel option enabled.

`/etc/init.d/rtirq status` gives you an overview about the current IRQ status.

To load the kernel with the threadirqs option, edit `/etc/default/grub` and change the line
```
GRUB_CMDLINE_LINUX=""
```
to
```
GRUB_CMDLINE_LINUX="threadirqs"
```
Then run `update-grub` with super-user privileges.

You can adapt the priorities given to specific interrupts to the needs of your setup depending if you are using a soudcard on the USB or firewire bus for instance. To do sp you can edit the rtirq config file, which typically will be installed in either of the directories:

```
/etc/sysconfig/rtirq
/etc/default/rtirq
```

The `RTIRQ_NAME_LIST` variable contains a list of space separated service names of which the first entry gets the highest priority. The term service seems to refer to module names and sound device designations (so the output of lsmod and aplay -l respectively) and doesn't have to correspond to the full output, part of the output may suffice as the rtirq script does the matching itself.

The `RTIRQ_PRIO_HIGH` variable sets the highest priority a service can get assigned.

The `RTIRQ_PRIO_DECR` lets you set the number with which the priorities for each consequent service mentioned in the `RTIRQ_NAME_LIST` variable should be decreased.

The `RTIRQ_RESET_ALL` is a legacy variable and can best be left to default.

The `RTIRQ_NON_THREADED` variable is another legacy option, your kernel configuration has to support it and in almost all cases it doesn't because the specific option, which was part of the `CONFIG_PREEMPT_VOLUNTARY` kernel config option and that allowed for setting non-threaded IRQs, simply doesn't exist anymore. So basically this variable doesn't do anything.

The `RTIRQ_HIGH_LIST` variable contains a list of space separated service names that get priorities in the 99-91 range, so above the value as set in the `RTIRQ_PRIO_HIGH` variable. Use this variable only for services of which you want to be 100% sure they don't get interrupted by anything else. You will mostly want to put timers in there like rtc or the ALSA high resolution timer (snd-hrtimer). 
