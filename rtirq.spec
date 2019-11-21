%define name    rtirq
%define version 20191121
%define release 38

%if %{defined fedora}
%define debug_package %{nil}
%endif

Summary:	Realtime IRQ thread system tunning
Name:		%{name}
Version:	%{version}
Release:	%{release}
License:	GPLv2+
Packager:	rncbc
Group:		System Environment/Base
Source0:	%{name}-%{version}.tar.gz
BuildRoot:	/var/tmp/%{name}-%{version}-buildroot
BuildArch:	noarch

BuildRequires:	util-linux,systemd
%if %{defined fedora}
BuildRequires:	chkconfig
%else
BuildRequires:	systemd-sysvinit,sysvinit-tools,insserv-compat
%endif

%if 0%{?suse_version}
Requires(post,preun): %insserv_prereq
%if ! %{defined _fillupdir}
%define _fillupdir /var/adm/fillup-templates
%endif
%endif

%description
Startup scripts for tunning the realtime scheduling policy and priority
of relevant IRQ service threads, featured for a PREEMPT_RT / threadirqs
enabled kernel configuration.

%prep

%setup

%build

%install
%__rm -rf %{buildroot}
install -vD rtirq.sh      -m 0755 %{buildroot}%{_sysconfdir}/init.d/rtirq
%if 0%{?suse_version}
install -vD rtirq.conf    -m 0644 %{buildroot}%{_fillupdir}/sysconfig.rtirq
%else
install -vD rtirq.conf    -m 0644 %{buildroot}%{_sysconfdir}/sysconfig/rtirq
%endif
install -vD rtirq.service -m 0644 %{buildroot}%{_prefix}/lib/systemd/system/rtirq.service
install -vD rtirq-resume.service -m 0644 %{buildroot}%{_prefix}/lib/systemd/system/rtirq-resume.service
install -d %{buildroot}%{_sbindir}
ln -svf %{_sysconfdir}/init.d/rtirq %{buildroot}%{_sbindir}/rtirq

%post
%if 0%{?suse_version}
%{fillup_and_insserv -y rtirq}
%endif
# Only run on install, not upgrade.
if [ "$1" = "1" ]; then
    chkconfig --add rtirq
    chkconfig rtirq on
fi
systemctl enable rtirq.service
systemctl enable rtirq-resume.service

%preun
# Only run if this is the last instance to be removed.
if [ "$1" = "0" ]; then
    chkconfig rtirq off
    chkconfig --del rtirq
fi
%if 0%{?suse_version}
%{stop_on_removal rtirq}
%insserv_cleanup
%endif
systemctl disable rtirq-resume.service
systemctl disable rtirq.service

%clean
%__rm -rf %{buildroot}

%files
%defattr(-,root,root)
%dir %{_sysconfdir}/init.d
%{_sysconfdir}/init.d/rtirq
%{_sbindir}/rtirq
%if 0%{?suse_version}
%config(noreplace) %{_fillupdir}/sysconfig.rtirq
%else
%config(noreplace) %{_sysconfdir}/sysconfig/rtirq
%endif
%dir %{_prefix}/lib/systemd
%dir %{_prefix}/lib/systemd/system
%{_prefix}/lib/systemd/system/rtirq.service
%{_prefix}/lib/systemd/system/rtirq-resume.service

%changelog
* Thu Nov 21 2019 Rui Nuno Capela <rncbc@rncbc.org>
- Created debian packaging files.
* Tue Jan 29 2019 Rui Nuno Capela <rncbc@rncbc.org>
- Restart rtirq service after resume from suspend (by Térence Clastres).
- Fix for some Intel internal and USB stuff (by Samuel Pelegrinello).
- Version 20190129.
* Fri Feb  9 2018 Rui Nuno Capela <rncbc@rncbc.org>
- Always reset/stop to scheduling policy=SCHED_FIFO and priority=50.
- Version 20180209.
* Mon Feb 16 2015 Rui Nuno Capela <rncbc@rncbc.org>
- Added "xhci_hcd" (USB 3.x) to "usb" keyword roster.
- Removed (old) "rtc" from default config list.
- Version 20150216.
* Sun Apr 13 2014 Rui Nuno Capela <rncbc@rncbc.org>
- Fixed shared IRQ issues on same service class (eg. snd).
- Version 20140413.
* Mon Sep  9 2013 Rui Nuno Capela <rncbc@rncbc.org>
- After targets added to systemd unit.
- Version 20130909.
* Tue Apr  2 2013 Rui Nuno Capela <rncbc@rncbc.org>
- Include systemd unit (by Simon Lewis).
- Version 20130402.
* Mon Nov  5 2012 Rui Nuno Capela <rncbc@rncbc.org>
- Version 20121105.
* Sat May  5 2012 Rui Nuno Capela <rncbc@rncbc.org>
- Version 20120505.
* Fri Oct  7 2011 Rui Nuno Capela <rncbc@rncbc.org>
- Version 20111007.
* Mon Mar 14 2011 Rui Nuno Capela <rncbc@rncbc.org>
- Version 20110314.
* Sun Sep 20 2009 Rui Nuno Capela <rncbc@rncbc.org>
- Version 20090920.
* Fri Sep 11 2009 Rui Nuno Capela <rncbc@rncbc.org>
- Fixed for rtc being missed on newer kernel-rt >= 2.6.31. 
- Version 20090911.
* Mon Aug 10 2009 Rui Nuno Capela <rncbc@rncbc.org>
- Fixed some specific gawk regex particles for portability sake.
- Version 20090810.
* Sat Aug  8 2009 Rui Nuno Capela <rncbc@rncbc.org>
- Starting from kernel-rt >= 2.6.31 the IRQ service threads are
  now being separate to its own and corresponding device-driver,
  giving chance for shared IRQ line tuning resolution.
- Version up to 20090828.
* Fri Jun 26 2009 Rui Nuno Capela <rncbc@rncbc.org>
- Fix status on newer kernels naming soft-irq threads with this
  shorter prefix "sirq-..." instead of older "softirq-...".
- Version bump to 20090626.
* Sat Jan 31 2009 Rui Nuno Capela <rncbc@rncbc.org>
- Ubuntustudio contributed patches.
- LICENSE file added to distribution tarball.
* Fri Oct 12 2007 Rui Nuno Capela <rncbc@rncbc.org>
* Mon Jan 1 2007 Rui Nuno Capela <rncbc@rncbc.org>
- Force bash as specific shell interpreter.
- Add default support for alternate configuration file locations.
- Stamped with 20071012 version.
* Sat Dec 16 2006 Rui Nuno Capela <rncbc@rncbc.org>
- Make headers clear that this is GPLed software.
- Got rid of those softirq-timer highest priority by default.
- Going up for 20061216 encarnation.
* Sat Aug 19 2006 Rui Nuno Capela <rncbc@rncbc.org>
- Apparently the echo to /proc/...threaded does not like a final CR,
  as noted by Fernando Lopez-Lezcano on a PREEMPT_DESKTOP kernel.
- Bumped to 20060819 version.
* Thu Aug 17 2006 Rui Nuno Capela <rncbc@rncbc.org>
- Bumped to 20060817 version.
* Sat Feb 18 2006 Rui Nuno Capela <rncbc@rncbc.org>
- Set all softirq-timers to highest priority; 20060218 version.
* Wed Sep 14 2005 Rui Nuno Capela <rncbc@rncbc.org>
- Touched to 20050914 version.
* Tue Aug 16 2005 Rui Nuno Capela <rncbc@rncbc.org>
- Fixed to 20050816 version.
* Mon Jun 20 2005 Rui Nuno Capela <rncbc@rncbc.org>
- Up to 20050620 tinyfix version.
* Wed Jun  8 2005 Rui Nuno Capela <rncbc@rncbc.org>
- Fixes on non threading IRQ service (thanks to Luis Garrido).
- Bumped to 20050608 version.
* Wed Jun  1 2005 Rui Nuno Capela <rncbc@rncbc.org>
- Missing info on status list was fixed for IRQs>99. 
- Moved to 20050601 version.
* Fri Apr 15 2005 Rui Nuno Capela <rncbc@rncbc.org>
- Non threading IRQ service list configuration option.
- Moved to 20050415 version.
* Fri Apr  8 2005 Rui Nuno Capela <rncbc@rncbc.org>
- IRQ handler refrence name included on status listing.
- Prevent lower priority overriding due to shared IRQs.
- Fixed to 20050408 version.
* Fri Nov 12 2004 Rui Nuno Capela <rncbc@rncbc.org>
- Bumped to 20041112 version.
* Mon Nov  8 2004 Rui Nuno Capela <rncbc@rncbc.org>
- Update for the new 20041108 version.
* Thu Nov  4 2004 Rui Nuno Capela <rncbc@rncbc.org>
- Created initial rtirq.spec
