#!/bin/bash
#
# Apply hpc2n preferences for min/max on ganglia RRD:s that are historically
# troublesome.

# This script is explicitly unlicensed, so you can base whatever site
# specific thing you want to do on it.

# This is free and unencumbered software released into the public domain.
#
# Anyone is free to copy, modify, publish, use, compile, sell, or
# distribute this software, either in source code form or as a compiled
# binary, for any purpose, commercial or non-commercial, and by any
# means.
#
# In jurisdictions that recognize copyright laws, the author or authors
# of this software dedicate any and all copyright interest in the
# software to the public domain. We make this dedication for the benefit
# of the public at large and to the detriment of our heirs and
# successors. We intend this dedication to be an overt act of
# relinquishment in perpetuity of all present and future rights to this
# software under copyright law.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
# For more information, please refer to <https://unlicense.org>


# Add main script dir, ie our uplevel dir, to PATH
dir=$(dirname $0)
export PATH=$PATH:$dir/..

export RRDCACHED_ADDRESS="unix:/var/run/rrdcached.sock"

# Dual 25 gigabit with a factor of 2 margin if reporting is uneven over time
let netmax=2*2*25*1000*1000*1000/8

# Derive max packet rate from network rate (84 bytes is the minimum ethernet
# packet size) and round it to even millions
let pktmax=$netmax/84/1000000*1000000

# More than 100 GB/s aggregated is highly unlikely for writes.
# Read rates include cache hits however, so scales with number of nodes.
let lustremaxbw=100*1000*1000*1000
# 10M IOPS is probably generous
let lustremaxiops=10*1000*1000
# file_ops are all filedata calls (read/write/stat/ioctl/open/close/etc)
# Base it on reading maxbw with 1k blocks
let lustremaxfops=$lustremaxbw/1000

set-ganglia-rrd-limits.pl \
	"(bytes|pkts)_(in|out).rrd:--minimum:0:regex" \
	"bytes_(in|out).rrd:--maximum:$netmax:regex,suminfosqrt" \
	"pkts_(in|out).rrd:--maximum:$pktmax:regex,suminfosqrt" \
	"cpu_(aidle|idle|nice|system|user|wio).rrd:--minimum:0:regex" \
	"cpu_(aidle|idle|nice|system|user|wio).rrd:--maximum:100:regex" \
	"lusclt_[a-z0-9]+_((file|inode)_ops|(read|write)_bytes_per_sec).rrd:--minimum:0:regex" \
	"lusclt_[a-z0-9]+_write_bytes_per_sec.rrd:--maximum:$lustremaxbw:regex,suminfoval" \
	"lusclt_[a-z0-9]+_read_bytes_per_sec.rrd:--maximum:$lustremaxbw:regex,suminfosqrt" \
	"lusclt_[a-z0-9]+_inode_ops:--maximum:$lustremaxiops:regex,suminfoval" \
	"lusclt_[a-z0-9]+_file_ops:--maximum:$lustremaxfops:regex,suminfoval"
