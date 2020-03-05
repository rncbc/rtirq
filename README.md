# rtirq
rtirq - Startup script for realtime-preempt enabled kernels

Your package manager may make this package availabe as `rtirq-init`.

This script allows to make use of the threaded IRQs as used by real-time kernels or kernels >= 2.6.39 with the threadirqs kernel option enabled.

`/etc/init.d/rtirq status` gives you an overview about the current IRQ settings

Typically the configuration file will be installed in either of the directories:

```
/etc/sysconfig/rtirq
/etc/default/rtirq
```
