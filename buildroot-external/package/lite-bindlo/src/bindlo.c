/*
 * openccu-lite: libbindlo.so, an LD_PRELOAD shim for hmipserver's unit.
 *
 * hmipserver's HTTP server (VirtualDevices, /groups, /bidcos and the group pages) binds its port
 * (HMServer.conf's hmServerPort, 39292) to every interface, and has no setting for a bind address;
 * only its XML-RPC port has one (Legacy.BindAddress). This shim turns a bind() of the wildcard
 * address to a port listed in BINDLO_PORTS (comma-separated) into the loopback: `::` becomes
 * `::ffff:127.0.0.1` on an IPv6 socket - the shape Legacy.BindAddress gives the XML-RPC port -
 * and `0.0.0.0` becomes `127.0.0.1`. Every other bind() passes through unchanged.
 *
 * A shim that cannot be loaded is only logged by ld.so, and the port is then open again; occulited
 * checks after hmipserver's start that the port is bound to the loopback and warns when it is not.
 *
 * Copyright 2026 openccu-lite contributors. Apache-2.0.
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <dlfcn.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <syslog.h>

static int (*real_bind)(int, const struct sockaddr *, socklen_t);

/* whether port is one of BINDLO_PORTS */
static int wanted(unsigned short port)
{
	const char *s = getenv("BINDLO_PORTS");
	char buf[128], *save = NULL;

	if (!s || !*s)
		return 0;
	strncpy(buf, s, sizeof(buf) - 1);
	buf[sizeof(buf) - 1] = 0;
	for (char *t = strtok_r(buf, ",", &save); t; t = strtok_r(NULL, ",", &save))
		if (atoi(t) == port)
			return 1;
	return 0;
}

int bind(int fd, const struct sockaddr *addr, socklen_t len)
{
	if (!real_bind)
		real_bind = (int (*)(int, const struct sockaddr *, socklen_t))dlsym(RTLD_NEXT, "bind");
	if (!real_bind)
		return -1;

	if (addr && addr->sa_family == AF_INET6 && len >= sizeof(struct sockaddr_in6)) {
		struct sockaddr_in6 a;
		memcpy(&a, addr, sizeof(a));
		if (IN6_IS_ADDR_UNSPECIFIED(&a.sin6_addr) && wanted(ntohs(a.sin6_port))) {
			inet_pton(AF_INET6, "::ffff:127.0.0.1", &a.sin6_addr);
			syslog(LOG_INFO, "bindlo: port %u bound to the loopback", ntohs(a.sin6_port));
			return real_bind(fd, (struct sockaddr *)&a, sizeof(a));
		}
	} else if (addr && addr->sa_family == AF_INET && len >= sizeof(struct sockaddr_in)) {
		struct sockaddr_in a;
		memcpy(&a, addr, sizeof(a));
		if (a.sin_addr.s_addr == htonl(INADDR_ANY) && wanted(ntohs(a.sin_port))) {
			a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
			syslog(LOG_INFO, "bindlo: port %u bound to the loopback", ntohs(a.sin_port));
			return real_bind(fd, (struct sockaddr *)&a, sizeof(a));
		}
	}
	return real_bind(fd, addr, len);
}
