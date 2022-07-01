#!/bin/sh
#
# rshall_ext.readinfo - Use readinfo to extract and format data for rshall use.
#
# Copyright (c) 2008 Occam's Razor. All rights reserved.
#
# See the LICENSE file distributed with this code for restrictions on its use
# and further distribution.
# Original distribution available at <http://www.occam.com/tools/>.
#
# $Id: rshall_ext.readinfo.sh,v 1.0 2008/05/03 19:40:28 leonvs Exp $
#

readinfoCmd="/usr/local/bin/readinfo"
hostFile="/usr/local/etc/systems"

$readinfoCmd -P -N -i $hostFile host os hw loc comment ssh
