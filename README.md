# OSG Software and Release Tools

This repository contains miscellaneous scripts used primarily by the
OSG Software and Release teams.

Maintainer note:
Because UW CS cron jobs use some of these scripts, there is a clone of
this repo located at `/p/condor/workspaces/vdt/tools` on UW AFS.  After
merging or making changes to the "master" branch, don't forget to do

```
cd /p/condor/workspaces/vdt/tools && git pull
```

so the cron jobs get the updated scripts.

---

## Notes on individual tools
 - [`list-rpm-versions`](#list-rpm-versions)

---

### `list-rpm-versions`

This script is for listing rpm versions installed in an osg-test job output
or summarizing across an entire VMU run on osghost.  A copy is installed
there under `/usr/local/bin`.

Below are some use cases for reference / appetite whetting.

**TL;DR:** The most common use case will probably be the one at the end with `--summarize` and `--list-outputs` (`-sl` for short) run against the timestamp for a VMU run dir.

---

Usage & Options summary:
```
[edquist@osghost ~]
$ list-rpm-versions --help

Usage:
  list-rpm-versions [options] output-001 [packages...]
  list-rpm-versions [options] [--summarize] [run-]20161220-1618 packages...
  list-rpm-versions [options] VMU-RESULTS-URL packages...

List version-release numbers for RPMs installed in an osg-test run output
directory, as found in output-NNN/output/osg-test-*.log

The output argument can also be a root.log from a koji/mock build,
or the raw output of an 'rpm -qa' command, or an osg-profile.txt from
osg-system-profiler.

If any packages are specified, limit the results to just those packages.

Patterns can be specified for package names with the '%' character, which
matches like '*' in a shell glob pattern.

If a run directory (or, just the timstamp string) is specified, summary
information will be printed for the listed packages across all output-NNN
subdirectories for that set of osg test runs.

If a VMU-RESULTS-URL is provided, the corresponding run dir will be used.
Eg: "http://vdt.cs.wisc.edu/tests/20180604-1516/005/osg-test-20180604.log"
for an individual output job (005),
or: "http://vdt.cs.wisc.edu/tests/20180604-1516/packages.html"
for a summary of all jobs for the run.

Options:
  -A, --no-strip-arch  don't attempt to strip .arch from package names
  -D, --no-strip-dist  don't attempt to strip .dist tag from package releases

  -s, --summarize      summarize results for all output subdirs
                       (this option is implied if the argument specified is of
                       the format [run-]YYYYMMDD-HHMM)
  -l, --list-outputs   list output numbers (summarize mode only)
  -L, --max-outputs N  list at most N output numbers per NVR (-1 for unlimited)
```


Example run on a single `output-NNN` dir for all packages:
```
[edquist@osghost /osgtest/runs/run-20161221-0423]
$ list-rpm-versions output-123 

Package                         output-123
-------                         ----------
CGSI-gSOAP                      1.3.10-1
GConf2                          3.2.6-8
apache-commons-cli              1.2-13
apache-commons-codec            1.8-7
apache-commons-collections      3.2.1-22
apache-commons-discovery        2:0.5-9
apache-commons-io               1:2.4-12
apache-commons-lang             2.6-15
apache-commons-logging          1.1.2-7
apr                             1.4.8-3
apr-util                        1.5.2-6
atk                             2.14.0-1
audit-libs-python               2.4.1-5
avalon-framework                4.3-10
...
```


Example run on a single `output-NNN` dir for two packages:
```
[edquist@osghost /osgtest/runs/run-20161221-0423]
$ list-rpm-versions output-123 condor java-1.7.0-openjdk

Package             output-123
-------             ----------
condor              8.5.8-1.osgup
java-1.7.0-openjdk  1:1.7.0.121-2.6.8.0
```


Example run in summary mode over all `output-NNN` subdirs for a run set:
```
[edquist@osghost ~]
$ list-rpm-versions -s 20161221-0423 condor java-1.7.0-openjdk

Package             Version-Release      Count
-------             ---------------      -----
condor              -                    5
condor              8.4.9-1              63
condor              8.4.10-1             105
condor              8.5.7-1.osgup        42
condor              8.5.8-1.osgup        79

java-1.7.0-openjdk  -                    5
java-1.7.0-openjdk  1:1.7.0.121-2.6.8.0  121
java-1.7.0-openjdk  1:1.7.0.121-2.6.8.1  168
```


Same thing, but list the output dir numbers also:
```
[edquist@osghost ~]
$ list-rpm-versions -sl 20161221-0423 condor java-1.7.0-openjdk

Package             Version-Release      Count  Output-Nums
-------             ---------------      -----  -----------
condor              -                    5      075,078,080,082,083
condor              8.4.9-1              63     000,001,002,003,004,005,006,...
condor              8.4.10-1             105    007,008,009,010,011,012,013,...
condor              8.5.7-1.osgup        42     021,022,023,024,025,026,027,...
condor              8.5.8-1.osgup        79     028,029,030,031,032,033,034,...

java-1.7.0-openjdk  -                    5      075,078,080,082,083
java-1.7.0-openjdk  1:1.7.0.121-2.6.8.0  121    000,001,002,003,004,005,006,...
java-1.7.0-openjdk  1:1.7.0.121-2.6.8.1  168    126,127,128,129,130,131,132,...
```

