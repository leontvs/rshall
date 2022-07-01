# $Id: Makefile,v 7.3 2015/11/02 02:17:53 leonvs Exp $

INST_ROOT=~

BIN=${INST_ROOT}/bin
BINMODE=0555

ETC=${INST_ROOT}/etc
ETCMODE=0444

# Modern BSD-style install; you may need to modify
INSTALL=/usr/bin/install -bp -o leon.townsvonstauber -m
#INSTALL=/usr/ucb/install -o root -m	# Solaris SunOS-compatible install
#INSTALL=/usr/bin/installbsd -c -o root -m	# AIX BSD-compatible install

install:
	${INSTALL} ${BINMODE} rshall.pl ${BIN}/rshall
	if [ -L ${BIN}/cpall ]; then /bin/rm ${BIN}/cpall; fi
	/bin/ln -s rshall ${BIN}/cpall
	if [ -L ${BIN}/sqall ]; then /bin/rm ${BIN}/sqall; fi
	/bin/ln -s rshall ${BIN}/sqall
	${INSTALL} ${BINMODE} rshall_ext.readinfo.sh ${BIN}/rshall_ext.readinfo
	${INSTALL} ${BINMODE} rshall_ext.mysql.pl ${BIN}/rshall_ext.mysql
	[ -f ${ETC}/systems ] || ${INSTALL} ${ETCMODE} systems ${ETC}/systems

