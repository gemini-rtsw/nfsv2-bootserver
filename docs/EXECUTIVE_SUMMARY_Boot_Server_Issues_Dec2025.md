# Gemini North Boot Server Infrastructure: Post-Shutdown Issues & Resolution

## Executive Summary for Telescope Leadership

**Date:** December 5, 2025  
**Author:** Software Team  
**Status:** RESOLVED

---

## Root Cause Identified

**A faulty fiber optic cable at the summit was dropping approximately 0.6% of network packets.**

For UDP-based communications (used by NFSv2 for legacy VxWorks/RTEMS boot operations), even this small packet loss rate caused catastrophic performance degradation. UDP relies on software-level error correction, and the legacy boot protocols were unable to handle the packet loss gracefully.

### Verification
- After the faulty fiber was removed from service, TCS successfully booted from its original boot server for the **first time in over a month**
- HRWFS was moved back to Pisces and booted **without issues**

---

## Timeline of Events

### Historical Context (Pre-2025)

| Date | Event | Reference |
|------|-------|-----------|
| March 11, 2024 | Pisces memory usage issues causing slow boots; slab cache at 100% | [ITOPS-11769](https://noirlab.atlassian.net/servicedesk/customer/portal/4/ITOPS-11769) |
| March 14, 2024 | Altair slow boot issues on Pisces; high TCP timeouts/retransmissions, NFS slowdowns | [GNFR-73679](https://noirlab.atlassian.net/browse/GNFR-73679) |

**Historical Analysis from ITOPS-11769 (March 2024):**

Pisces memory usage slowly increased over time until full, then slow boots started:
- **slabtop showed 100% slab cache usage**
- Memory grew from 550MB (Friday) to 3.05GB (Monday) with only 8GB available
- Rebooting the VM temporarily resolved the issue
- **Suspected cause:** NFS default max threads was set to 8
- **Actions taken:** Increased memory and raised NFS thread count to 16
- **⚠️ Note:** These fixes may have been coincidental; the faulty fiber was likely the true underlying cause

**Historical Analysis from GNFR-73679 (March 2024):**

The March 2024 incident documented similar symptoms to the October 2025 issues:
- **9,602 failed connection attempts** logged on Pisces
- **40,721 TCP timeouts** and **40,433 connections aborted due to timeout**
- TCP connections stuck in unusual states (`FIN_WAIT1`, `SYN_SENT`)
- NFS server running with 90-second grace period causing delays

**Key observations from IT Operations (Chris Stark, March 2024):**
> "NFS server performance on Linux has always been problematic compared to other platforms, especially in older versions of the Linux kernel – and PISCES running on CentOS 6 most definitely applies. On these older versions of the kernel, I've noticed that NFS performance degrades gradually but consistently until the NFS service is restarted or the system is rebooted."

**Actions taken at the time:**
1. Boosted PISCES VM resources (CPU cores: 2→8, RAM: 2GB→8GB)
2. Weekly/bi-weekly reboot schedule recommended for Pisces

**⚠️ Note:** In retrospect, these 2024 fixes may have had minimal impact and could have been a red herring. The underlying network issue (faulty fiber) was likely present but not identified until late 2025.


### During October Shutdown (October 14-28, 2025)

| Date | Event | Reference |
|------|-------|-----------|
| Oct 14-28 | Scheduled shutdown; network changes made | — |
| Oct 23, 2025 | HRWFS and Altair experiencing extremely long boots/hangs | [GNFR-74908](https://noirlab.atlassian.net/browse/GNFR-74908) |
| Oct 29, 2025 | TCS disconnected | [GNFR-74910](https://noirlab.atlassian.net/browse/GNFR-74910) |

### After October Shutdown (October 28 – December 2, 2025)

| Date | Event | Reference |
|------|-------|-----------|
| Oct 28, 2025 | Shutdown ends; boot issues persist | — |
| Oct 30, 2025 | Altair on split boot servers (1X on new server, others on Pisces) | [GNFR-74912](https://noirlab.atlassian.net/browse/GNFR-74912) |
| Nov 3, 2025 | Altair circular buffers not fully writing to `/net/pisces/altair_snap` | [GNFR-74927](https://noirlab.atlassian.net/browse/GNFR-74927) |
| **Nov 8, 2025 (Fri)** | **⚠️ KEY EVENT: TCS crash** - original boot server (mkortprd-lv1) unresponsive | — |
| Nov 8, 2025 | TCS boot moved to mkortprd-lv2 as workaround | — |
| Nov 8, 2025 | Ephemeris file access issues discovered after server change | [GNFR-74951](https://noirlab.atlassian.net/browse/GNFR-74951) |
| Nov 10, 2025 | CR documentation for TCS boot location change | [PFTWGN-365](https://noirlab.atlassian.net/browse/PFTWGN-365) |
| Nov 10, 2025 | Work begins on new Altair boot server | [PFTWGN-363](https://noirlab.atlassian.net/browse/PFTWGN-363) |
| Nov 12, 2025 | TCS crash during observing (0.78 hr time lost) - RPCIO error | [GNFR-74958](https://noirlab.atlassian.net/browse/GNFR-74958) |
| Nov 13-26, 2025 | **Recurring TCS RPCIO errors** - 7 additional faults logged | See RPCIO Summary below |
| Late Nov 2025 | **Root cause found:** Simon Chan identified faulty fiber dropping ~0.6% packets | — |
| Dec 2, 2025 | **Permanent fix:** New TCS boot server set to production | [PFTWGN-375](https://noirlab.atlassian.net/browse/PFTWGN-375) |
| Dec 2, 2025 | **Permanent fix:** New Altair boot server set to production | [PFTWGN-374](https://noirlab.atlassian.net/browse/PFTWGN-374) |
| Dec 2, 2025 | HRWFS moved back to Pisces (now working) | [PFTWGN-376](https://noirlab.atlassian.net/browse/PFTWGN-376) |

---

## TCS RPCIO Error Summary

**Friday, November 8, 2025 was the critical turning point.** The TCS crashed because the original boot server (mkortprd-lv1) was unresponsive. As a workaround, the TCS boot was moved to mkortprd-lv2.

**Sequence of issues:**
1. **Ephemeris file access issue** (GNFR-74951) - first problem discovered after the server change; **this was fixed**
2. **Subsequent RPCIO errors** - caused by running an **older TCS version** on mkortprd-lv2 (the only version that would run); RPCIO errors were a **known issue with that older version**

[GNFR-74951](https://noirlab.atlassian.net/browse/GNFR-74951) was designated as the **master fault** for tracking purposes:

| Ticket | Date | Description |
|--------|------|-------------|
| — | **Nov 8, 2025 (Fri)** | **⚠️ TRIGGERING EVENT** - TCS crash; mkortprd-lv1 unresponsive |
| [GNFR-74951](https://noirlab.atlassian.net/browse/GNFR-74951) | Nov 8, 2025 | **Master fault** - Ephemeris file access issue (**fixed**) |
| [GNFR-74958](https://noirlab.atlassian.net/browse/GNFR-74958) | Nov 12, 2025 | TCS crash during observing (0.78 hr lost) - older TCS version issue |
| [GNFR-74965](https://noirlab.atlassian.net/browse/GNFR-74965) | Nov 2025 | RPCIO error - known issue with older TCS version on mkortprd-lv2 |
| [GNFR-74969](https://noirlab.atlassian.net/browse/GNFR-74969) | Nov 2025 | RPCIO error - known issue with older TCS version on mkortprd-lv2 |
| [GNFR-74977](https://noirlab.atlassian.net/browse/GNFR-74977) | Nov 2025 | RPCIO error - known issue with older TCS version on mkortprd-lv2 |
| [GNFR-74989](https://noirlab.atlassian.net/browse/GNFR-74989) | Nov 2025 | RPCIO error - known issue with older TCS version on mkortprd-lv2 |
| [GNFR-74990](https://noirlab.atlassian.net/browse/GNFR-74990) | Nov 2025 | RPCIO error - known issue with older TCS version on mkortprd-lv2 |
| [GNFR-74995](https://noirlab.atlassian.net/browse/GNFR-74995) | Nov 2025 | RPCIO error - known issue with older TCS version on mkortprd-lv2 |
| [GNFR-74996](https://noirlab.atlassian.net/browse/GNFR-74996) | Nov 2025 | RPCIO error - known issue with older TCS version on mkortprd-lv2 |

**Typical error pattern:**
```
RPCIO: server '10.2.71.11' not responding - still trying
NFS (proc 6) - RPC: Timed out
```

---

## Affected Systems

| System | Issue | Impact | Resolution |
|--------|-------|--------|------------|
| **Altair (VxWorks)** | Boot taking overnight; CBs not writing | AO facility unavailable | New boot server at 10.2.2.147/148 |
| **TCS (RTEMS)** | RPCIO errors; crashes during observing | Telescope control unavailable | New boot server at 10.2.2.145/146 |
| **HRWFS (VxWorks)** | 20+ minute boots | A&G unavailable | Returned to Pisces after fiber fix |
| **Ephemeris files** | TCS couldn't read files for non-sidereal tracking | Moving object observing impossible | Moved to new TCS boot server |

---

## Symptoms Observed

### Boot Server Symptoms
- Boots taking **overnight** instead of <1 minute
- **RPCIO errors** and timeouts
- `portmap` failures
- Files truncating or failing to write completely
- Circular buffer dumps failing with "Invalid Shape in writeBuffer: num[1] = 0"

### Network Analysis (VxWorks Large File Write Investigation)

| Metric | Degraded Period | Excellent Period | Difference |
|--------|-----------------|------------------|------------|
| Avg Throughput | 1.76 MBit/s | 30.36 MBit/s | **17× better** |
| Consistency | Erratic | Sustained | Stable |
| Stall Rate | ~2% packets | <0.5% packets | **4× fewer** |
| Network Loss | 0% (appeared) | 0% | Identical |

**Key Finding:** The system could deliver 30 Mbit/s sustained when server I/O was responsive. Server delays varied unpredictably, resulting in a **17× performance swing**.

---

## Solutions Implemented

### 1. Faulty Fiber Removed (Root Cause Fix)
- Simon Chan identified and removed the faulty fiber
- This restored normal operations to Pisces-based boot services
- HRWFS returned to Pisces successfully

### 2. New TCS Boot Server Infrastructure
**Production Servers:**
- **mkotcsboot-lv1 (10.2.2.146)** — NFSv3/4 host services
- **Container (10.2.2.145)** — NFSv2/TFTP for RTEMS VME boot

**Mount Points Updated:**
- `/gemsoft/var/data/ephemerides` → `mkotcsboot-lv1:/gem_sw/etc/rtconfig/ephemerides`
- `/gemsoft/var/data/tcs` → `mkotcsboot-lv1:/gem_sw/etc/rtconfig/tcs`

**Reference:** [PFTWGN-375](https://noirlab.atlassian.net/browse/PFTWGN-375)

### 3. New Altair Boot Server Infrastructure
**Production Servers:**
- **mkoaltboot-lv1 (10.2.2.148)** — NFSv3/4 for workstation/YAC mounts
- **mkoaltbootv2-lv1 (10.2.2.147)** — NFSv2/RSH/RCP container for VxWorks

**Mount Point Updated:**
- `/gemsoft/var/data/altair` → `mkoaltboot-lv1:/export`

**Reference:** [PFTWGN-374](https://noirlab.atlassian.net/browse/PFTWGN-374)

---

## Clarification: The 16KB Write Truncation Issue

During development of the new Altair boot server, a **separate issue** was discovered where files larger than 16KB were being truncated. This was **NOT the root cause** of the post-shutdown problems, but rather a bug in the initial NFSv2 container configuration.

### Technical Details
- Files written through NFS were truncating at exactly 16,384 bytes
- Root cause: Three different files defined `NFS_MAXDATA` with inconsistent values
  - `nfsd.c` — updated to 32KB
  - `nfs_prot.h` — still 8KB (bug)
  - `nfs_prot.x` — still 8KB (bug)
- **Fix:** Updated all three files to 32KB consistently

This was fixed as part of the new boot server deployment and is not related to the fiber issue.

---

## Boot Server Inventory

### Legacy Boot Servers

| Server | IP Address | OS | Protocol | Clients | Status |
|--------|------------|-----|----------|---------|--------|
| pisces | 10.2.2.57 | CentOS 6.10 | NFSv2 (kernel) | HRWFS, Altair (historical) | Active - HRWFS returned after fiber fix |
| mkortprd-lv1 | 10.2.71.11 | CentOS 6.10 | NFSv2 | TCS (original), EPICS 3.14.12.7 RTEMS | Deprecated - unresponsive Nov 2025 |
| mkortprd-lv2 | 10.2.71.12 | CentOS 7.9 | NFSv2 | TCS (temporary), EPICS 3.14.12.8 RTEMS | Used as temporary fallback Nov 2025 |
| mkortnfs-lv1 | 10.2.71.30 | CentOS 6.10 | NFSv2 | EPICS 7 RTEMS | Active |

### New Boot Servers (Deployed Dec 2025)

**Altair Boot Infrastructure:**

| Server | IP Address | OS | Protocol | Purpose |
|--------|------------|-----|----------|---------|
| mkoaltboot-lv1 | 10.2.2.148 | Rocky 9 | NFSv3/4 | Host server - workstation/YAC mounts |
| mkoaltbootv2-lv1 | 10.2.2.147 | Docker container | NFSv2, RSH, RCP | VxWorks boot services |

**TCS Boot Infrastructure:**

| Server | IP Address | OS | Protocol | Purpose |
|--------|------------|-----|----------|---------|
| mkotcsboot-lv1 | 10.2.2.146 | Rocky 9 | NFSv3/4 | Host server - workstation mounts |
| (container) | 10.2.2.145 | Docker container | NFSv2, TFTP | RTEMS VME boot services |

---

## Current Production Configuration

### Altair Boot Settings

| Board | Boot Server | IP |
|-------|-------------|-----|
| IOC | mkoaltbootv2-lv1 | 10.2.2.147 |
| 1X | mkoaltbootv2-lv1 | 10.2.2.147 |
| 2X | mkoaltbootv2-lv1 | 10.2.2.147 |
| 1Y | mkoaltbootv2-lv1 | 10.2.2.147 |
| 2Y | mkoaltbootv2-lv1 | 10.2.2.147 |

### TCS Boot Settings

| Parameter | Value |
|-----------|-------|
| Client IP | 10.2.2.104 |
| Server IP | 10.2.2.145 |
| Boot File | gem_sw/prod/redirector/tcs-mk-ioc |

### HRWFS Boot Settings

| Parameter | Value |
|-----------|-------|
| Host | pisces-control |
| Server IP | 10.2.2.57 |
| Status | Returned to original server after fiber fix |

---

## Documentation & Resources

| Resource | Location |
|----------|----------|
| TCS Boot Server Setup | [Confluence: Rtems TCS Boot Server](https://noirlab.atlassian.net/wiki/spaces/~5fc7051ad670b8006e0402ba/pages/18372690017/Rtems+TCS+Boot+Server) |
| Altair Boot Server Setup | [Confluence: Altair Boot Server Setup](https://noirlab.atlassian.net/wiki/spaces/~5fc7051ad670b8006e0402ba/pages/18372689925/Altair+Boot+Server+Setup) |
| NFSv2 Boot Server Code | [GitLab: nfsv2-bootserver](https://gitlab.com/nsf-noirlab/gemini/rtsw/nfsv2-bootserver) |
| IT Operations Ticket | [ITOPS-18423](https://noirlab.atlassian.net/servicedesk/customer/portal/4/ITOPS-18423) |

---

## Related Jira Tickets

### Slow Boot Fault Reports

**Historical (Pre-2025):**
- [ITOPS-11769](https://noirlab.atlassian.net/servicedesk/customer/portal/4/ITOPS-11769) — Pisces memory/slab cache issues (March 2024); NFS threads increased 8→16 (Sept 2024)
- [GNFR-73679](https://noirlab.atlassian.net/browse/GNFR-73679) — Pisces slow boots with Altair (March 2024) - 9,602 failed connections, 40K+ TCP timeouts

**October-November 2025:**
- [GNFR-74908](https://noirlab.atlassian.net/browse/GNFR-74908) — HRWFS and Altair long boots/hangs (Oct 23, 2025)
- [GNFR-74910](https://noirlab.atlassian.net/browse/GNFR-74910) — TCS disconnected (Oct 29, 2025)
- [GNFR-74912](https://noirlab.atlassian.net/browse/GNFR-74912) — Altair WFCS TT Limit error (consequence of boot issues)

### TCS Fault Reports
- [GNFR-74951](https://noirlab.atlassian.net/browse/GNFR-74951) — **Master fault (Nov 8):** Ephemeris file access issue (**fixed**)
- [GNFR-74958](https://noirlab.atlassian.net/browse/GNFR-74958) — TCS crash during observing (0.78 hr lost)

**Subsequent RPCIO errors** (due to older TCS version on mkortprd-lv2 - known issue):
- [GNFR-74965](https://noirlab.atlassian.net/browse/GNFR-74965), [GNFR-74969](https://noirlab.atlassian.net/browse/GNFR-74969), [GNFR-74977](https://noirlab.atlassian.net/browse/GNFR-74977), [GNFR-74989](https://noirlab.atlassian.net/browse/GNFR-74989), [GNFR-74990](https://noirlab.atlassian.net/browse/GNFR-74990), [GNFR-74995](https://noirlab.atlassian.net/browse/GNFR-74995), [GNFR-74996](https://noirlab.atlassian.net/browse/GNFR-74996)

### Altair Data/CB Issues
- [GNFR-74927](https://noirlab.atlassian.net/browse/GNFR-74927) — Altair CBs not writing to `/net/pisces/altair_snap`

### Change Requests (Completed)
- [PFTWGN-374](https://noirlab.atlassian.net/browse/PFTWGN-374) — New Altair boot server to production
- [PFTWGN-375](https://noirlab.atlassian.net/browse/PFTWGN-375) — New TCS boot server to production
- [PFTWGN-376](https://noirlab.atlassian.net/browse/PFTWGN-376) — HRWFS back to Pisces
- [PFTWGN-363](https://noirlab.atlassian.net/browse/PFTWGN-363) — Altair boot server work
- [PFTWGN-365](https://noirlab.atlassian.net/browse/PFTWGN-365) — Temporary TCS boot location

---

## Key Takeaways

1. **Root Cause:** A single faulty fiber caused ~0.6% packet loss, catastrophic for UDP-based legacy protocols
2. **Time to Resolution:** ~5 weeks from symptom onset to root cause identification
3. **Historical Pattern:** VxWorks/RTEMS slow boot issues have been recurring since at least March 2024 (GNFR-73679), suggesting systemic infrastructure limitations with the aging Pisces server (CentOS 6.10)
4. **Outcome:** New boot server infrastructure deployed for both TCS and Altair, providing:
   - Modern NFSv3/4 services for workstations
   - Containerized NFSv2 services for legacy VxWorks/RTEMS systems
   - Improved reliability and maintainability
   - Separation from aging Pisces infrastructure
5. **Lessons Learned:** 
   - Small packet loss rates can cause severe degradation in UDP-based protocols
   - Legacy NFSv2 systems need specialized infrastructure support
   - CentOS 6 kernel NFS performance degrades over time without restarts
   - New boot server infrastructure provides better isolation and maintainability

---

## Recommendation

**This investigation highlights the need for better visibility into network infrastructure.** Access to network data, metrics, and diagnostic information would significantly accelerate future troubleshooting efforts. The root cause (0.6% packet loss on a fiber) was only identified after weeks of investigation—earlier access to network-level metrics could have shortened this timeline considerably.

---

## Contacts

| Role | Name |
|------|------|
| Software Team Lead | Hawi Stecher |
| Network Investigation | Simon Chan |
| IT Operations | Chris Stark |

---

*Document generated: December 5, 2025*

